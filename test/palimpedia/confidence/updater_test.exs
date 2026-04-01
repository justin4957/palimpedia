defmodule Palimpedia.Confidence.UpdaterTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Confidence.{Updater, Scorer}
  alias Palimpedia.Graph.{Node, Edge}

  defmodule MockRepo do
    @moduledoc false

    # Track calls via process dictionary for assertions
    def update_confidence(node_id, confidence, anchor_distance) do
      send(self(), {:update_confidence, node_id, confidence, anchor_distance})

      {:ok,
       %Node{
         id: node_id,
         title: "Updated",
         node_type: :generated,
         confidence: confidence,
         anchor_distance: anchor_distance
       }}
    end

    def shortest_anchor_distance(1, _), do: {:ok, 0}
    def shortest_anchor_distance(2, _), do: {:ok, 1}
    def shortest_anchor_distance(3, _), do: {:ok, nil}
    def shortest_anchor_distance(_, _), do: {:ok, 2}

    def anchor_sources(1, _) do
      {:ok,
       [
         %Node{
           id: 1,
           title: "Anchor",
           node_type: :anchor,
           confidence: 1.0,
           provenance: ["wikidata:Q1"]
         }
       ]}
    end

    def anchor_sources(2, _) do
      {:ok,
       [
         %Node{
           id: 1,
           title: "Anchor",
           node_type: :anchor,
           confidence: 1.0,
           provenance: ["wikidata:Q1"]
         }
       ]}
    end

    def anchor_sources(_, _), do: {:ok, []}

    def subgraph(_, 1), do: {:ok, [], []}

    def subgraph(center_id, 2) do
      {:ok,
       [
         %Node{
           id: 1,
           title: "Anchor",
           node_type: :anchor,
           confidence: 1.0,
           anchor_distance: 0,
           provenance: ["wikidata:Q1"]
         },
         %Node{
           id: 2,
           title: "Generated A",
           node_type: :generated,
           confidence: 0.5,
           anchor_distance: 1,
           provenance: ["wikidata:Q1"],
           generated_at: DateTime.utc_now()
         },
         %Node{
           id: 3,
           title: "Generated B",
           node_type: :generated,
           confidence: 0.0,
           anchor_distance: nil,
           provenance: [],
           generated_at: DateTime.utc_now()
         }
       ],
       [
         %Edge{
           id: 100,
           source_id: 1,
           target_id: 2,
           edge_type: :references,
           confidence: 1.0
         }
       ]}
    end

    def find_ungrounded(max_distance, opts) do
      {:ok,
       [
         %Node{
           id: 99,
           title: "Ungrounded",
           node_type: :generated,
           confidence: 0.1,
           anchor_distance: max_distance + 1
         }
       ]}
    end
  end

  describe "recalculate_node/2" do
    test "updates confidence from graph data" do
      node = %Node{
        id: 2,
        title: "Generated",
        node_type: :generated,
        confidence: 0.0,
        anchor_distance: nil,
        provenance: [],
        generated_at: DateTime.utc_now()
      }

      assert {:ok, updated} = Updater.recalculate_node(node, MockRepo)
      assert updated.confidence > 0.0
      assert updated.anchor_distance == 1

      assert_received {:update_confidence, 2, confidence, 1}
      assert confidence > 0.0
    end
  end

  describe "recalculate_subgraph/3" do
    test "recalculates all non-anchor nodes in neighborhood" do
      assert {:ok, result} = Updater.recalculate_subgraph(1, MockRepo, hops: 2)

      # 2 non-anchor nodes in the mock subgraph
      assert result.updated == 2
      assert result.errors == []
    end

    test "skips anchor nodes" do
      assert {:ok, result} = Updater.recalculate_subgraph(1, MockRepo, hops: 2)

      # Should not have received update for node 1 (anchor)
      refute_received {:update_confidence, 1, _, _}
    end
  end

  describe "apply_edge_propagation/3" do
    test "propagates confidence from anchor to ungrounded node" do
      anchor = %Node{
        id: 1,
        title: "Anchor",
        node_type: :anchor,
        confidence: 1.0,
        anchor_distance: 0,
        provenance: ["wikidata:Q1"]
      }

      ungrounded = %Node{
        id: 3,
        title: "Ungrounded",
        node_type: :generated,
        confidence: 0.0,
        anchor_distance: nil,
        provenance: []
      }

      result = Updater.apply_edge_propagation(anchor, ungrounded, MockRepo)
      assert result.updated == 1
      assert result.errors == []

      assert_received {:update_confidence, 3, confidence, 1}
      assert confidence > 0.0
    end

    test "no propagation when neither node is grounded" do
      a = %Node{
        id: 10,
        title: "A",
        node_type: :generated,
        confidence: 0.0,
        anchor_distance: nil,
        provenance: []
      }

      b = %Node{
        id: 11,
        title: "B",
        node_type: :generated,
        confidence: 0.0,
        anchor_distance: nil,
        provenance: []
      }

      result = Updater.apply_edge_propagation(a, b, MockRepo)
      assert result.updated == 0
    end
  end

  describe "find_regrounding_candidates/2" do
    test "returns nodes beyond max hops" do
      assert {:ok, nodes} = Updater.find_regrounding_candidates(MockRepo)
      assert length(nodes) > 0
      assert hd(nodes).title == "Ungrounded"
    end
  end
end
