defmodule Palimpedia.Federation.Protocol do
  @moduledoc """
  Federation protocol: message format and serialization for
  inter-instance subgraph sharing.

  ## Message Types

  - `:subgraph_share` — Share a subgraph segment with a peer
  - `:edge_assertion` — Forward a user edge assertion to peers
  - `:sync_request` — Request subgraph updates from a peer
  - `:sync_response` — Response containing requested subgraph data

  ## Wire Format

  Messages are JSON-encoded with a standard envelope:
  ```json
  {
    "protocol": "palimpedia-federation/1.0",
    "type": "subgraph_share",
    "source_instance": "instance-id",
    "timestamp": "2026-04-02T...",
    "payload": { ... }
  }
  ```
  """

  @protocol_version "palimpedia-federation/1.0"

  @type message_type :: :subgraph_share | :edge_assertion | :sync_request | :sync_response

  @type message :: %{
          protocol: String.t(),
          type: message_type(),
          source_instance: String.t(),
          timestamp: String.t(),
          payload: map()
        }

  @doc "Encodes a federation message to JSON."
  def encode(type, payload, source_instance) do
    message = %{
      protocol: @protocol_version,
      type: Atom.to_string(type),
      source_instance: source_instance,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      payload: payload
    }

    Jason.encode(message)
  end

  @doc "Decodes a JSON federation message."
  def decode(json) when is_binary(json) do
    with {:ok, parsed} <- Jason.decode(json),
         :ok <- validate_protocol(parsed) do
      {:ok,
       %{
         protocol: parsed["protocol"],
         type: String.to_existing_atom(parsed["type"]),
         source_instance: parsed["source_instance"],
         timestamp: parsed["timestamp"],
         payload: parsed["payload"]
       }}
    end
  rescue
    ArgumentError -> {:error, :invalid_message_type}
  end

  @doc "Returns the current protocol version."
  def version, do: @protocol_version

  @doc "Serializes a subgraph (nodes + edges) for federation sharing."
  def serialize_subgraph(nodes, edges) do
    %{
      nodes:
        Enum.map(nodes, fn node ->
          %{
            title: node.title,
            content: node.content,
            node_type: Atom.to_string(node.node_type),
            confidence: node.confidence,
            provenance: node.provenance,
            anchor_distance: node.anchor_distance,
            generated_at: node.generated_at && DateTime.to_iso8601(node.generated_at)
          }
        end),
      edges:
        Enum.map(edges, fn edge ->
          %{
            source_title: find_title(nodes, edge.source_id),
            target_title: find_title(nodes, edge.target_id),
            edge_type: Atom.to_string(edge.edge_type),
            confidence: edge.confidence,
            provenance: edge.provenance
          }
        end),
      node_count: length(nodes),
      edge_count: length(edges)
    }
  end

  @doc "Deserializes a subgraph payload into node and edge structs for import."
  def deserialize_subgraph(payload) do
    nodes =
      Enum.map(payload["nodes"] || [], fn n ->
        %Palimpedia.Graph.Node{
          title: n["title"],
          content: n["content"],
          node_type: safe_atom(n["node_type"], :generated),
          confidence: n["confidence"] || 0.0,
          provenance: n["provenance"] || [],
          anchor_distance: n["anchor_distance"]
        }
      end)

    edges =
      Enum.map(payload["edges"] || [], fn e ->
        %{
          source_title: e["source_title"],
          target_title: e["target_title"],
          edge_type: safe_atom(e["edge_type"], :related_to),
          confidence: e["confidence"] || 0.0,
          provenance: e["provenance"] || []
        }
      end)

    {:ok, nodes, edges}
  end

  defp validate_protocol(%{"protocol" => @protocol_version}), do: :ok
  defp validate_protocol(%{"protocol" => other}), do: {:error, {:unsupported_protocol, other}}
  defp validate_protocol(_), do: {:error, :missing_protocol}

  defp find_title(nodes, node_id) do
    case Enum.find(nodes, &(&1.id == node_id)) do
      nil -> "unknown"
      node -> node.title
    end
  end

  defp safe_atom(str, default) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> default
  end

  defp safe_atom(_, default), do: default
end
