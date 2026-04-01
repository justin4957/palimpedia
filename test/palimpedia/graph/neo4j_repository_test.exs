defmodule Palimpedia.Graph.Neo4jRepositoryTest do
  use ExUnit.Case

  @moduletag :integration

  alias Palimpedia.Graph.{Neo4jRepository, Node, Edge}

  setup do
    # Clean the test database before each test
    :ok = Neo4jRepository.delete_all()
    :ok
  end

  describe "insert_node/1" do
    test "inserts an anchor node and returns it with an ID" do
      node =
        Node.new_anchor(
          "Quantum Mechanics",
          "The study of matter at atomic scale.",
          "wikidata:Q944"
        )

      assert {:ok, inserted} = Neo4jRepository.insert_node(node)
      assert is_integer(inserted.id)
      assert inserted.title == "Quantum Mechanics"
      assert inserted.content == "The study of matter at atomic scale."
      assert inserted.node_type == :anchor
      assert inserted.confidence == 1.0
      assert inserted.anchor_distance == 0
      assert inserted.provenance == ["wikidata:Q944"]
    end

    test "inserts a generated node with timestamp" do
      node =
        Node.new_generated("Bridge: QM and Relativity", "Connecting two frameworks.",
          confidence: 0.7,
          provenance: ["wikidata:Q944", "wikidata:Q11379"],
          anchor_distance: 1
        )

      assert {:ok, inserted} = Neo4jRepository.insert_node(node)
      assert is_integer(inserted.id)
      assert inserted.node_type == :generated
      assert inserted.confidence == 0.7
      assert inserted.anchor_distance == 1
      assert inserted.generated_at != nil
    end

    test "inserts a requested node placeholder" do
      node = Node.new_request("Dark Matter")

      assert {:ok, inserted} = Neo4jRepository.insert_node(node)
      assert is_integer(inserted.id)
      assert inserted.node_type == :requested
      assert inserted.confidence == 0.0
      assert inserted.content == nil
    end
  end

  describe "get_node/1" do
    test "retrieves a previously inserted node" do
      {:ok, inserted} =
        Neo4jRepository.insert_node(
          Node.new_anchor(
            "General Relativity",
            "Einstein's theory of gravitation.",
            "wikidata:Q11379"
          )
        )

      assert {:ok, fetched} = Neo4jRepository.get_node(inserted.id)
      assert fetched.id == inserted.id
      assert fetched.title == "General Relativity"
      assert fetched.node_type == :anchor
      assert fetched.confidence == 1.0
    end

    test "returns :not_found for nonexistent ID" do
      assert {:error, :not_found} = Neo4jRepository.get_node(999_999_999)
    end
  end

  describe "insert_edge/1" do
    test "creates a typed edge between two nodes" do
      {:ok, source} =
        Neo4jRepository.insert_node(
          Node.new_anchor("Quantum Mechanics", "QM content", "wikidata:Q944")
        )

      {:ok, target} =
        Neo4jRepository.insert_node(
          Node.new_anchor("General Relativity", "GR content", "wikidata:Q11379")
        )

      edge = %Edge{
        source_id: source.id,
        target_id: target.id,
        edge_type: :related_to,
        confidence: 0.9,
        provenance: ["wikidata:Q944"]
      }

      assert {:ok, inserted_edge} = Neo4jRepository.insert_edge(edge)
      assert is_integer(inserted_edge.id)
      assert inserted_edge.source_id == source.id
      assert inserted_edge.target_id == target.id
      assert inserted_edge.edge_type == :related_to
      assert inserted_edge.confidence == 0.9
    end

    test "supports all valid edge types" do
      {:ok, source} = Neo4jRepository.insert_node(Node.new_anchor("A", "a", "src:1"))
      {:ok, target} = Neo4jRepository.insert_node(Node.new_anchor("B", "b", "src:2"))

      for edge_type <- Edge.valid_types() do
        edge = %Edge{
          source_id: source.id,
          target_id: target.id,
          edge_type: edge_type,
          confidence: 0.5,
          provenance: []
        }

        assert {:ok, inserted} = Neo4jRepository.insert_edge(edge),
               "Failed to insert edge type: #{edge_type}"

        assert inserted.edge_type == edge_type
      end
    end

    test "rejects invalid edge types" do
      assert {:error, {:invalid_edge_type, :bogus}} =
               Neo4jRepository.insert_edge(%Edge{
                 source_id: 1,
                 target_id: 2,
                 edge_type: :bogus,
                 confidence: 0.5,
                 provenance: []
               })
    end
  end

  describe "subgraph/2" do
    test "retrieves the local neighborhood of a node" do
      {:ok, center} = Neo4jRepository.insert_node(Node.new_anchor("Center", "center", "src:c"))
      {:ok, neighbor_one} = Neo4jRepository.insert_node(Node.new_anchor("N1", "n1", "src:1"))
      {:ok, neighbor_two} = Neo4jRepository.insert_node(Node.new_anchor("N2", "n2", "src:2"))
      {:ok, distant} = Neo4jRepository.insert_node(Node.new_anchor("Distant", "far", "src:d"))

      # Center -> N1, Center -> N2, N2 -> Distant
      Neo4jRepository.insert_edge(%Edge{
        source_id: center.id,
        target_id: neighbor_one.id,
        edge_type: :references,
        confidence: 0.8,
        provenance: []
      })

      Neo4jRepository.insert_edge(%Edge{
        source_id: center.id,
        target_id: neighbor_two.id,
        edge_type: :supports,
        confidence: 0.7,
        provenance: []
      })

      Neo4jRepository.insert_edge(%Edge{
        source_id: neighbor_two.id,
        target_id: distant.id,
        edge_type: :derived_from,
        confidence: 0.6,
        provenance: []
      })

      # 1-hop: should include center, N1, N2 but NOT distant
      assert {:ok, nodes_1, edges_1} = Neo4jRepository.subgraph(center.id, 1)
      node_ids_1 = Enum.map(nodes_1, & &1.id) |> MapSet.new()
      assert MapSet.member?(node_ids_1, center.id)
      assert MapSet.member?(node_ids_1, neighbor_one.id)
      assert MapSet.member?(node_ids_1, neighbor_two.id)
      refute MapSet.member?(node_ids_1, distant.id)
      assert length(edges_1) == 2

      # 2-hop: should include all four nodes
      assert {:ok, nodes_2, edges_2} = Neo4jRepository.subgraph(center.id, 2)
      node_ids_2 = Enum.map(nodes_2, & &1.id) |> MapSet.new()
      assert MapSet.member?(node_ids_2, center.id)
      assert MapSet.member?(node_ids_2, distant.id)
      assert length(edges_2) == 3
    end

    test "returns the center node even with no edges" do
      {:ok, lonely} = Neo4jRepository.insert_node(Node.new_anchor("Lonely", "alone", "src:l"))

      assert {:ok, nodes, edges} = Neo4jRepository.subgraph(lonely.id, 1)
      assert length(nodes) == 1
      assert hd(nodes).id == lonely.id
      assert edges == []
    end
  end

  describe "search_nodes/2" do
    test "finds nodes by title substring" do
      Neo4jRepository.insert_node(Node.new_anchor("Quantum Mechanics", "qm", "src:1"))
      Neo4jRepository.insert_node(Node.new_anchor("Quantum Computing", "qc", "src:2"))
      Neo4jRepository.insert_node(Node.new_anchor("General Relativity", "gr", "src:3"))

      assert {:ok, results} = Neo4jRepository.search_nodes("Quantum")
      assert length(results) == 2
      assert Enum.all?(results, fn n -> String.contains?(n.title, "Quantum") end)
    end

    test "respects the limit option" do
      for i <- 1..5 do
        Neo4jRepository.insert_node(Node.new_anchor("Topic #{i}", "content", "src:#{i}"))
      end

      assert {:ok, results} = Neo4jRepository.search_nodes("Topic", limit: 2)
      assert length(results) == 2
    end

    test "returns empty list for no matches" do
      assert {:ok, []} = Neo4jRepository.search_nodes("nonexistent_xyz")
    end
  end

  describe "find_orphans/1" do
    test "returns nodes with no edges" do
      {:ok, connected_a} = Neo4jRepository.insert_node(Node.new_anchor("A", "a", "src:1"))
      {:ok, connected_b} = Neo4jRepository.insert_node(Node.new_anchor("B", "b", "src:2"))
      {:ok, orphan} = Neo4jRepository.insert_node(Node.new_anchor("Orphan", "alone", "src:3"))

      Neo4jRepository.insert_edge(%Edge{
        source_id: connected_a.id,
        target_id: connected_b.id,
        edge_type: :references,
        confidence: 0.5,
        provenance: []
      })

      assert {:ok, orphans} = Neo4jRepository.find_orphans()
      orphan_ids = Enum.map(orphans, & &1.id)
      assert orphan.id in orphan_ids
      refute connected_a.id in orphan_ids
      refute connected_b.id in orphan_ids
    end
  end

  describe "delete_all/0" do
    test "removes all nodes and relationships" do
      Neo4jRepository.insert_node(Node.new_anchor("A", "a", "src:1"))
      Neo4jRepository.insert_node(Node.new_anchor("B", "b", "src:2"))

      assert :ok = Neo4jRepository.delete_all()

      assert {:ok, results} = Neo4jRepository.search_nodes("A")
      assert results == []
    end
  end
end
