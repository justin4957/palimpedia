defmodule Palimpedia.Confidence.ProvenanceChainTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Confidence.ProvenanceChain
  alias Palimpedia.Graph.Node

  # Mock graph repository for provenance tests
  defmodule MockRepo do
    @moduledoc false

    def shortest_anchor_distance(1, _max_hops), do: {:ok, 0}
    def shortest_anchor_distance(2, _max_hops), do: {:ok, 2}
    def shortest_anchor_distance(3, _max_hops), do: {:ok, nil}
    def shortest_anchor_distance(4, _max_hops), do: {:ok, 5}
    def shortest_anchor_distance(_, _), do: {:ok, nil}

    def anchor_sources(1, _max_hops) do
      {:ok,
       [
         %Node{
           id: 1,
           title: "Self Anchor",
           node_type: :anchor,
           confidence: 1.0,
           provenance: ["wikidata:Q1"]
         }
       ]}
    end

    def anchor_sources(2, _max_hops) do
      {:ok,
       [
         %Node{
           id: 10,
           title: "Distant Anchor",
           node_type: :anchor,
           confidence: 1.0,
           provenance: ["arxiv:123"]
         }
       ]}
    end

    def anchor_sources(3, _max_hops), do: {:ok, []}
    def anchor_sources(4, _max_hops), do: {:ok, []}
    def anchor_sources(_, _), do: {:ok, []}

    # Node 3 has edges (citation loop), node 5 has no edges (orphan)
    def subgraph(3, 1),
      do:
        {:ok, [%Node{id: 3, title: "Loop", node_type: :generated}],
         [%{id: 100, source_id: 3, target_id: 6, edge_type: :references}]}

    def subgraph(_, 1), do: {:ok, [], []}
  end

  describe "trace/3" do
    test "anchor node is grounded with distance 0" do
      assert {:ok, result} = ProvenanceChain.trace(1, MockRepo)

      assert result.node_id == 1
      assert result.anchor_distance == 0
      assert result.grounded == true
      assert result.citation_loop == false
      assert length(result.anchor_sources) == 1
    end

    test "generated node with anchor path is grounded" do
      assert {:ok, result} = ProvenanceChain.trace(2, MockRepo)

      assert result.anchor_distance == 2
      assert result.grounded == true
      assert result.citation_loop == false
    end

    test "ungrounded node with edges is flagged as citation loop" do
      assert {:ok, result} = ProvenanceChain.trace(3, MockRepo)

      assert result.anchor_distance == nil
      assert result.grounded == false
      assert result.citation_loop == true
      assert result.anchor_sources == []
    end

    test "ungrounded node beyond max hops" do
      assert {:ok, result} = ProvenanceChain.trace(4, MockRepo)

      assert result.anchor_distance == 5
      assert result.grounded == true
      assert result.citation_loop == false
    end
  end

  describe "trace_batch/3" do
    test "traces multiple nodes" do
      assert {:ok, results} = ProvenanceChain.trace_batch([1, 2, 3], MockRepo)

      assert map_size(results) == 3
      assert results[1].grounded == true
      assert results[2].grounded == true
      assert results[3].grounded == false
    end
  end

  describe "citation_loop?/3" do
    test "detects citation loops" do
      assert ProvenanceChain.citation_loop?(3, MockRepo) == true
    end

    test "grounded nodes are not loops" do
      assert ProvenanceChain.citation_loop?(1, MockRepo) == false
      assert ProvenanceChain.citation_loop?(2, MockRepo) == false
    end
  end
end
