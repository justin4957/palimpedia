defmodule Palimpedia.GapDetection.GapIntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  alias Palimpedia.Graph.{Neo4jRepository, Node, Edge}
  alias Palimpedia.GapDetection.Analyzer

  setup do
    :ok = Neo4jRepository.delete_all()
    :ok
  end

  describe "find_low_connectivity/2" do
    test "returns nodes with fewer than N edges" do
      {:ok, well_connected} =
        Neo4jRepository.insert_node(Node.new_anchor("Hub", "center", "src:h"))

      {:ok, leaf_a} = Neo4jRepository.insert_node(Node.new_anchor("Leaf A", "a", "src:a"))
      {:ok, leaf_b} = Neo4jRepository.insert_node(Node.new_anchor("Leaf B", "b", "src:b"))
      {:ok, loner} = Neo4jRepository.insert_node(Node.new_anchor("Loner", "alone", "src:l"))

      Neo4jRepository.insert_edge(%Edge{
        source_id: well_connected.id,
        target_id: leaf_a.id,
        edge_type: :references,
        confidence: 1.0,
        provenance: []
      })

      Neo4jRepository.insert_edge(%Edge{
        source_id: well_connected.id,
        target_id: leaf_b.id,
        edge_type: :references,
        confidence: 1.0,
        provenance: []
      })

      Neo4jRepository.insert_edge(%Edge{
        source_id: leaf_a.id,
        target_id: leaf_b.id,
        edge_type: :related_to,
        confidence: 0.5,
        provenance: []
      })

      {:ok, results} = Neo4jRepository.find_low_connectivity(2)

      node_ids = Enum.map(results, fn %{node: n} -> n.id end)
      # Loner has 0 edges, should be in results
      assert loner.id in node_ids
      # Well-connected hub has 2+ edges, should NOT be in results
      refute well_connected.id in node_ids
    end
  end

  describe "find_structural_holes/2" do
    test "detects pairs connected via intermediaries but not directly" do
      {:ok, a} = Neo4jRepository.insert_node(Node.new_anchor("A", "a", "src:a"))
      {:ok, bridge} = Neo4jRepository.insert_node(Node.new_anchor("Bridge", "b", "src:b"))
      {:ok, c} = Neo4jRepository.insert_node(Node.new_anchor("C", "c", "src:c"))

      # A -- Bridge -- C (A and C have no direct edge)
      Neo4jRepository.insert_edge(%Edge{
        source_id: a.id,
        target_id: bridge.id,
        edge_type: :references,
        confidence: 1.0,
        provenance: []
      })

      Neo4jRepository.insert_edge(%Edge{
        source_id: bridge.id,
        target_id: c.id,
        edge_type: :references,
        confidence: 1.0,
        provenance: []
      })

      {:ok, holes} = Neo4jRepository.find_structural_holes(3)

      # A and C should be detected as a structural hole
      pair_ids = Enum.map(holes, fn h -> MapSet.new([h.node_a.id, h.node_b.id]) end)
      expected = MapSet.new([a.id, c.id])
      assert expected in pair_ids
    end
  end

  describe "coverage_by_type/0" do
    test "returns per-type statistics" do
      Neo4jRepository.insert_node(Node.new_anchor("A", "a", "src:1"))
      Neo4jRepository.insert_node(Node.new_anchor("B", "b", "src:2"))

      {:ok, gen} =
        Neo4jRepository.insert_node(
          Node.new_generated("G", "g", confidence: 0.5, anchor_distance: 1)
        )

      {:ok, coverage} = Neo4jRepository.coverage_by_type()

      assert Map.has_key?(coverage, "anchor")
      assert coverage["anchor"].node_count == 2
    end
  end

  describe "full analyzer integration" do
    test "analyze detects gaps in a graph with structural holes" do
      {:ok, a} = Neo4jRepository.insert_node(Node.new_anchor("Physics", "science", "src:a"))
      {:ok, b} = Neo4jRepository.insert_node(Node.new_anchor("Bridge", "bridge", "src:b"))
      {:ok, c} = Neo4jRepository.insert_node(Node.new_anchor("Philosophy", "wisdom", "src:c"))
      {:ok, orphan} = Neo4jRepository.insert_node(Node.new_anchor("Orphan", "alone", "src:o"))

      Neo4jRepository.insert_edge(%Edge{
        source_id: a.id,
        target_id: b.id,
        edge_type: :references,
        confidence: 1.0,
        provenance: []
      })

      Neo4jRepository.insert_edge(%Edge{
        source_id: b.id,
        target_id: c.id,
        edge_type: :references,
        confidence: 1.0,
        provenance: []
      })

      {:ok, result} = Analyzer.analyze(graph_repo: Neo4jRepository)

      assert result.stats.total_gaps > 0
      assert result.stats.orphans >= 1

      gap_types = Enum.map(result.gaps, & &1.gap_type) |> MapSet.new()
      assert :orphan in gap_types
    end
  end
end
