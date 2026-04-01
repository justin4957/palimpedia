defmodule Palimpedia.Generation.ResponseParser do
  @moduledoc """
  Parses structured JSON output from the LLM generation pipeline.

  Extracts title, content, claims with confidence scores, typed edges,
  and contradiction flags from the generated response.
  """

  alias Palimpedia.Graph.Edge

  @type parsed_response :: %{
          title: String.t(),
          content: String.t(),
          claims: [claim()],
          edges: [edge_assertion()],
          contradictions: [contradiction()]
        }

  @type claim :: %{
          text: String.t(),
          confidence: float(),
          provenance: [String.t()]
        }

  @type edge_assertion :: %{
          target_title: String.t(),
          edge_type: Edge.edge_type(),
          confidence: float()
        }

  @type contradiction :: %{
          existing_node_title: String.t(),
          description: String.t()
        }

  @doc """
  Parses the LLM response text into a structured result.

  Expects JSON with keys: title, content, claims, edges, contradictions.
  Handles both raw JSON strings and JSON embedded in markdown code blocks.
  """
  def parse(response_text) when is_binary(response_text) do
    json_text = extract_json(response_text)

    case Jason.decode(json_text) do
      {:ok, parsed} -> extract_fields(parsed)
      {:error, _} -> {:error, {:parse_failed, "Response is not valid JSON"}}
    end
  end

  def parse(_), do: {:error, {:parse_failed, "Response must be a string"}}

  # --- Private ---

  defp extract_json(text) do
    # Try to extract JSON from markdown code blocks first
    case Regex.run(~r/```(?:json)?\s*\n?(.*?)\n?\s*```/s, text) do
      [_, json] -> String.trim(json)
      nil -> String.trim(text)
    end
  end

  defp extract_fields(parsed) when is_map(parsed) do
    with {:ok, title} <- required_string(parsed, "title"),
         {:ok, content} <- required_string(parsed, "content") do
      {:ok,
       %{
         title: title,
         content: content,
         claims: parse_claims(parsed["claims"]),
         edges: parse_edges(parsed["edges"]),
         contradictions: parse_contradictions(parsed["contradictions"])
       }}
    end
  end

  defp extract_fields(_), do: {:error, {:parse_failed, "Expected a JSON object"}}

  defp required_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_field, key}}
    end
  end

  defp parse_claims(nil), do: []

  defp parse_claims(claims) when is_list(claims) do
    claims
    |> Enum.map(&parse_claim/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_claims(_), do: []

  defp parse_claim(%{"text" => text} = claim) when is_binary(text) do
    %{
      text: text,
      confidence: parse_float(claim["confidence"], 0.5),
      provenance: parse_string_list(claim["provenance"])
    }
  end

  defp parse_claim(_), do: nil

  defp parse_edges(nil), do: []

  defp parse_edges(edges) when is_list(edges) do
    edges
    |> Enum.map(&parse_edge/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_edges(_), do: []

  defp parse_edge(%{"target_title" => target, "edge_type" => edge_type_str} = edge)
       when is_binary(target) and is_binary(edge_type_str) do
    case parse_edge_type(edge_type_str) do
      {:ok, edge_type} ->
        %{
          target_title: target,
          edge_type: edge_type,
          confidence: parse_float(edge["confidence"], 0.5)
        }

      :error ->
        nil
    end
  end

  defp parse_edge(_), do: nil

  defp parse_contradictions(nil), do: []

  defp parse_contradictions(contradictions) when is_list(contradictions) do
    contradictions
    |> Enum.map(&parse_contradiction/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_contradictions(_), do: []

  defp parse_contradiction(%{"existing_node_title" => title, "description" => description})
       when is_binary(title) and is_binary(description) do
    %{existing_node_title: title, description: description}
  end

  defp parse_contradiction(_), do: nil

  defp parse_edge_type(type_string) do
    normalized = type_string |> String.downcase() |> String.trim()

    try do
      atom = String.to_existing_atom(normalized)

      if atom in Edge.valid_types() do
        {:ok, atom}
      else
        :error
      end
    rescue
      ArgumentError -> :error
    end
  end

  defp parse_float(value, _default) when is_float(value), do: max(0.0, min(1.0, value))
  defp parse_float(value, _default) when is_integer(value), do: max(0.0, min(1.0, value / 1))
  defp parse_float(_, default), do: default

  defp parse_string_list(list) when is_list(list) do
    Enum.filter(list, &is_binary/1)
  end

  defp parse_string_list(_), do: []
end
