defmodule Palimpedia.Anchor.WikidataAdapter do
  @moduledoc """
  Adapter for ingesting entities from the Wikidata knowledge base.

  Fetches entities by QID (e.g. Q42), extracts labels, descriptions,
  and inter-entity relationships from claims. Maps Wikidata properties
  to Palimpedia edge types.
  """

  @behaviour Palimpedia.Anchor.Adapter

  @base_url "https://www.wikidata.org/w/api.php"

  # Wikidata properties mapped to Palimpedia edge types
  @property_to_edge_type %{
    "P31" => :specializes,
    "P279" => :generalizes,
    "P361" => :related_to,
    "P527" => :related_to,
    "P155" => :precedes,
    "P156" => :precedes,
    "P737" => :influences,
    "P941" => :derived_from,
    "P144" => :derived_from,
    "P1269" => :references,
    "P460" => :related_to,
    "P461" => :contradicts
  }

  @tracked_properties Map.keys(@property_to_edge_type)

  @impl true
  def fetch_entity(qid, opts \\ []) do
    fetch_entities([qid], opts)
  end

  @impl true
  def fetch_entities(qids, opts \\ []) do
    http_get = Keyword.get(opts, :http_client, &Palimpedia.Anchor.HttpClient.get/2)

    url =
      "#{@base_url}?action=wbgetentities&ids=#{Enum.join(qids, "|")}&format=json&languages=en&props=labels|descriptions|claims"

    case http_get.(url, []) do
      {:ok, %{status: 200, body: body}} ->
        parse_entities_response(body)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def search(query, opts \\ []) do
    http_get = Keyword.get(opts, :http_client, &Palimpedia.Anchor.HttpClient.get/2)
    limit = Keyword.get(opts, :limit, 20)

    url =
      "#{@base_url}?action=wbsearchentities&search=#{URI.encode(query)}&format=json&language=en&type=item&limit=#{limit}"

    case http_get.(url, []) do
      {:ok, %{status: 200, body: body}} ->
        qids = extract_search_qids(body)
        fetch_entities(qids, opts)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns the map of tracked Wikidata property IDs to Palimpedia edge types."
  def property_edge_mapping, do: @property_to_edge_type

  # --- Parsing ---

  defp parse_entities_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parse_entities_response(parsed)
      {:error, reason} -> {:error, {:json_parse_error, reason}}
    end
  end

  defp parse_entities_response(%{"entities" => entities}) do
    {all_entities, all_relationships} =
      entities
      |> Enum.reject(fn {_qid, data} -> Map.has_key?(data, "missing") end)
      |> Enum.reduce({[], []}, fn {qid, data}, {entities_acc, rels_acc} ->
        entity = extract_entity(qid, data)
        relationships = extract_relationships(qid, data)
        {[entity | entities_acc], relationships ++ rels_acc}
      end)

    {:ok, %{entities: Enum.reverse(all_entities), relationships: all_relationships}}
  end

  defp parse_entities_response(_body) do
    {:error, :unexpected_response_format}
  end

  defp extract_entity(qid, data) do
    label = get_in(data, ["labels", "en", "value"]) || qid
    description = get_in(data, ["descriptions", "en", "value"]) || ""

    %{
      title: label,
      content: description,
      source_id: "wikidata:#{qid}",
      properties: %{
        qid: qid,
        label: label,
        description: description
      }
    }
  end

  defp extract_relationships(source_qid, data) do
    claims = Map.get(data, "claims", %{})

    claims
    |> Enum.filter(fn {property_id, _} -> property_id in @tracked_properties end)
    |> Enum.flat_map(fn {property_id, claim_list} ->
      edge_type = Map.fetch!(@property_to_edge_type, property_id)

      claim_list
      |> Enum.map(fn claim -> extract_target_qid(claim) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn target_qid ->
        %{
          source_id: "wikidata:#{source_qid}",
          target_id: "wikidata:#{target_qid}",
          edge_type: edge_type,
          confidence: 1.0
        }
      end)
    end)
  end

  defp extract_target_qid(claim) do
    with %{"mainsnak" => mainsnak} <- claim,
         %{"datavalue" => datavalue} <- mainsnak,
         %{"value" => value} <- datavalue,
         %{"id" => target_qid} <- value do
      target_qid
    else
      _ -> nil
    end
  end

  defp extract_search_qids(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> extract_search_qids(parsed)
      _ -> []
    end
  end

  defp extract_search_qids(%{"search" => results}) do
    Enum.map(results, fn result -> result["id"] end)
  end

  defp extract_search_qids(_), do: []
end
