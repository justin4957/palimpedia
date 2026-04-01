defmodule Palimpedia.Anchor.Corpus.SeedIntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  alias Palimpedia.Graph.{Neo4jRepository, Node, Edge}

  setup do
    :ok = Neo4jRepository.delete_all()
    :ok
  end

  describe "graph report against seeded data" do
    test "stats reflect inserted nodes and edges" do
      # Insert a small seed dataset
      {:ok, anchor_a} =
        Neo4jRepository.insert_node(
          Node.new_anchor("Physics", "Science of matter", "wikidata:Q413")
        )

      {:ok, anchor_b} =
        Neo4jRepository.insert_node(
          Node.new_anchor("Quantum Mechanics", "Subfield of physics", "wikidata:Q944")
        )

      {:ok, anchor_c} =
        Neo4jRepository.insert_node(
          Node.new_anchor("Albert Einstein", "Physicist", "wikidata:Q937")
        )

      Neo4jRepository.insert_edge(%Edge{
        source_id: anchor_a.id,
        target_id: anchor_b.id,
        edge_type: :generalizes,
        confidence: 1.0,
        provenance: ["wikidata:Q413"]
      })

      Neo4jRepository.insert_edge(%Edge{
        source_id: anchor_c.id,
        target_id: anchor_b.id,
        edge_type: :influences,
        confidence: 1.0,
        provenance: ["wikidata:Q937"]
      })

      # Verify stats
      {:ok, stats} = Neo4jRepository.stats()
      assert stats.total_nodes == 3
      assert stats.total_edges == 2
      assert stats.anchor_nodes == 3
      assert stats.generated_nodes == 0
      assert stats.avg_confidence == 1.0
    end

    test "all anchor nodes have confidence 1.0 and anchor_distance 0" do
      Neo4jRepository.insert_node(Node.new_anchor("A", "content a", "src:1"))
      Neo4jRepository.insert_node(Node.new_anchor("B", "content b", "src:2"))
      Neo4jRepository.insert_node(Node.new_anchor("C", "content c", "src:3"))

      {:ok, nodes} = Neo4jRepository.search_nodes("", limit: 100)

      for node <- nodes do
        assert node.confidence == 1.0, "Node #{node.title} has confidence #{node.confidence}"

        assert node.anchor_distance == 0,
               "Node #{node.title} has anchor_distance #{node.anchor_distance}"

        assert node.node_type == :anchor
      end
    end

    test "graph is queryable via internal API after seeding" do
      {:ok, node} =
        Neo4jRepository.insert_node(Node.new_anchor("Test Entity", "For API test", "wikidata:Q1"))

      # Verify get_node works
      {:ok, fetched} = Neo4jRepository.get_node(node.id)
      assert fetched.title == "Test Entity"

      # Verify search works
      {:ok, results} = Neo4jRepository.search_nodes("Test", limit: 10)
      assert length(results) > 0

      # Verify subgraph works
      {:ok, nodes, edges} = Neo4jRepository.subgraph(node.id, 1)
      assert length(nodes) >= 1
    end
  end
end
