defmodule Palimpedia.Test.MockGraphRepo do
  @moduledoc """
  Mock graph repository for controller tests.
  Returns canned data without requiring Neo4j.
  """

  alias Palimpedia.Graph.{Node, Edge}

  @anchor %Node{
    id: 1,
    title: "Quantum Mechanics",
    content: "The study of matter at atomic scale.",
    node_type: :anchor,
    confidence: 1.0,
    anchor_distance: 0,
    provenance: ["wikidata:Q944"],
    metadata: %{}
  }

  @generated %Node{
    id: 2,
    title: "Quantum Entanglement",
    content: "A phenomenon where particles become linked.",
    node_type: :generated,
    confidence: 0.75,
    anchor_distance: 1,
    provenance: ["wikidata:Q944"],
    generated_at: ~U[2026-01-15 12:00:00Z],
    metadata: %{}
  }

  @edge %Edge{
    id: 100,
    source_id: 1,
    target_id: 2,
    edge_type: :generalizes,
    confidence: 0.9,
    provenance: ["wikidata:Q944"]
  }

  def get_node(1), do: {:ok, @anchor}
  def get_node(2), do: {:ok, @generated}
  def get_node(_), do: {:error, :not_found}

  def search_nodes("Quantum" <> _, opts) do
    limit = Keyword.get(opts, :limit, 20)
    {:ok, Enum.take([@anchor, @generated], limit)}
  end

  def search_nodes(_, _opts), do: {:ok, []}

  def insert_node(%Node{} = node) do
    {:ok, %{node | id: :erlang.unique_integer([:positive])}}
  end

  def insert_edge(%Edge{} = edge) do
    {:ok, %{edge | id: :erlang.unique_integer([:positive])}}
  end

  def subgraph(1, _hops), do: {:ok, [@anchor, @generated], [@edge]}
  def subgraph(2, _hops), do: {:ok, [@generated], []}
  def subgraph(_, _hops), do: {:error, :not_found}

  def stats do
    {:ok,
     %{
       total_nodes: 2,
       total_edges: 1,
       anchor_nodes: 1,
       generated_nodes: 1,
       requested_nodes: 0,
       bridge_nodes: 0,
       avg_confidence: 0.875
     }}
  end

  def find_orphans(_opts) do
    {:ok, []}
  end

  def delete_all, do: :ok
end
