defmodule Palimpedia.Confidence.ConfidenceIntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  alias Palimpedia.Graph.{Neo4jRepository, Node, Edge}
  alias Palimpedia.Confidence.{Scorer, ProvenanceChain, Updater}

  setup do
    :ok = Neo4jRepository.delete_all()
    :ok
  end

  describe "end-to-end confidence scoring" do
    test "anchor nodes always score 1.0" do
      {:ok, anchor} =
        Neo4jRepository.insert_node(
          Node.new_anchor("Physics", "The study of nature.", "wikidata:Q413")
        )

      assert anchor.confidence == 1.0
      assert anchor.anchor_distance == 0
    end

    test "generated node near anchor gets high confidence" do
      {:ok, anchor} =
        Neo4jRepository.insert_node(
          Node.new_anchor("Physics", "Science of matter.", "wikidata:Q413")
        )

      {:ok, generated} =
        Neo4jRepository.insert_node(
          Node.new_generated("Quantum Mechanics", "Subfield of physics.",
            confidence: 0.0,
            provenance: ["wikidata:Q413"],
            anchor_distance: 1
          )
        )

      Neo4jRepository.insert_edge(%Edge{
        source_id: anchor.id,
        target_id: generated.id,
        edge_type: :generalizes,
        confidence: 1.0,
        provenance: ["wikidata:Q413"]
      })

      {:ok, updated} = Updater.recalculate_node(generated, Neo4jRepository)
      assert updated.confidence > 0.0
      assert updated.anchor_distance == 1
    end

    test "update_confidence persists to graph" do
      {:ok, node} =
        Neo4jRepository.insert_node(
          Node.new_generated("Test", "content", confidence: 0.1, anchor_distance: 5)
        )

      {:ok, updated} = Neo4jRepository.update_confidence(node.id, 0.85, 2)
      assert updated.confidence == 0.85
      assert updated.anchor_distance == 2

      # Verify persistence
      {:ok, refetched} = Neo4jRepository.get_node(node.id)
      assert refetched.confidence == 0.85
      assert refetched.anchor_distance == 2
    end

    test "shortest_anchor_distance finds the minimum path" do
      {:ok, anchor} =
        Neo4jRepository.insert_node(Node.new_anchor("Root", "root", "src:root"))

      {:ok, hop1} =
        Neo4jRepository.insert_node(
          Node.new_generated("Hop 1", "h1", confidence: 0.5, anchor_distance: 1)
        )

      {:ok, hop2} =
        Neo4jRepository.insert_node(
          Node.new_generated("Hop 2", "h2", confidence: 0.3, anchor_distance: 2)
        )

      Neo4jRepository.insert_edge(%Edge{
        source_id: anchor.id,
        target_id: hop1.id,
        edge_type: :references,
        confidence: 1.0,
        provenance: []
      })

      Neo4jRepository.insert_edge(%Edge{
        source_id: hop1.id,
        target_id: hop2.id,
        edge_type: :references,
        confidence: 0.8,
        provenance: []
      })

      assert {:ok, 1} = Neo4jRepository.shortest_anchor_distance(hop1.id)
      assert {:ok, 2} = Neo4jRepository.shortest_anchor_distance(hop2.id)
    end

    test "find_ungrounded returns nodes beyond threshold" do
      Neo4jRepository.insert_node(
        Node.new_generated("Far Away", "far",
          confidence: 0.1,
          anchor_distance: 10
        )
      )

      Neo4jRepository.insert_node(
        Node.new_generated("Close", "close",
          confidence: 0.8,
          anchor_distance: 1
        )
      )

      {:ok, ungrounded} = Neo4jRepository.find_ungrounded(3)
      titles = Enum.map(ungrounded, & &1.title)
      assert "Far Away" in titles
      refute "Close" in titles
    end

    test "provenance chain traces through graph to anchors" do
      {:ok, anchor} =
        Neo4jRepository.insert_node(Node.new_anchor("Anchor", "base", "src:anchor"))

      {:ok, generated} =
        Neo4jRepository.insert_node(
          Node.new_generated("Generated", "derived", confidence: 0.0, anchor_distance: nil)
        )

      Neo4jRepository.insert_edge(%Edge{
        source_id: anchor.id,
        target_id: generated.id,
        edge_type: :derived_from,
        confidence: 1.0,
        provenance: []
      })

      {:ok, chain} = ProvenanceChain.trace(generated.id, Neo4jRepository)
      assert chain.grounded == true
      assert chain.anchor_distance == 1
      assert length(chain.anchor_sources) == 1
      assert hd(chain.anchor_sources).title == "Anchor"
    end

    test "orphan node without anchor path is ungrounded" do
      {:ok, orphan} =
        Neo4jRepository.insert_node(
          Node.new_generated("Orphan", "alone", confidence: 0.0, anchor_distance: nil)
        )

      {:ok, chain} = ProvenanceChain.trace(orphan.id, Neo4jRepository)
      assert chain.grounded == false
      assert chain.anchor_distance == nil
    end
  end
end
