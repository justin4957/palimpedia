defmodule PalimpediaWeb.GraphJSON do
  @moduledoc """
  JSON serialization for graph types.

  Every node response includes a confidence envelope:
  confidence score, anchor_distance, provenance chain, and
  whether the node requires regrounding.
  """

  alias Palimpedia.Graph.{Node, Edge}
  alias Palimpedia.Confidence.Scorer

  def node_to_json(%Node{} = node) do
    %{
      id: node.id,
      title: node.title,
      content: node.content,
      node_type: node.node_type,
      confidence: %{
        score: node.confidence,
        anchor_distance: node.anchor_distance,
        requires_regrounding: Scorer.requires_regrounding?(node.anchor_distance)
      },
      provenance: node.provenance,
      generated_at: node.generated_at && DateTime.to_iso8601(node.generated_at),
      metadata: node.metadata
    }
  end

  def edge_to_json(%Edge{} = edge) do
    %{
      id: edge.id,
      source_id: edge.source_id,
      target_id: edge.target_id,
      edge_type: edge.edge_type,
      confidence: edge.confidence,
      provenance: edge.provenance
    }
  end

  def nodes_to_json(nodes) when is_list(nodes) do
    Enum.map(nodes, &node_to_json/1)
  end

  def edges_to_json(edges) when is_list(edges) do
    Enum.map(edges, &edge_to_json/1)
  end
end
