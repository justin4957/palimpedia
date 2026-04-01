defmodule Palimpedia.Generation.PromptBuilderTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Generation.PromptBuilder
  alias Palimpedia.Graph.{Node, Edge}

  describe "build/4" do
    test "constructs prompt with system, context, and instructions" do
      nodes = [
        %Node{
          id: 1,
          title: "Physics",
          node_type: :anchor,
          confidence: 1.0,
          provenance: ["wikidata:Q413"]
        },
        %Node{
          id: 2,
          title: "Quantum Mechanics",
          node_type: :generated,
          confidence: 0.8,
          provenance: ["wikidata:Q413"]
        }
      ]

      edges = [
        %Edge{
          id: 100,
          source_id: 1,
          target_id: 2,
          edge_type: :generalizes,
          confidence: 0.9
        }
      ]

      result =
        PromptBuilder.build("Quantum Entanglement", nodes, edges, gap_type: :structural_hole)

      assert is_binary(result.system)
      assert String.contains?(result.system, "Palimpedia")
      assert result.context.target == "Quantum Entanglement"
      assert length(result.context.anchor_sources) == 1
      assert length(result.context.related_documents) == 1
      assert length(result.context.relationships) == 1
      assert result.context.gap_type == :structural_hole
      assert String.contains?(result.instructions, "Quantum Entanglement")
    end

    test "separates anchor and non-anchor nodes" do
      nodes = [
        %Node{id: 1, title: "A", node_type: :anchor, confidence: 1.0, provenance: ["src:1"]},
        %Node{id: 2, title: "B", node_type: :anchor, confidence: 1.0, provenance: ["src:2"]},
        %Node{id: 3, title: "C", node_type: :generated, confidence: 0.5, provenance: []}
      ]

      result = PromptBuilder.build("Target", nodes, [])
      assert length(result.context.anchor_sources) == 2
      assert length(result.context.related_documents) == 1
    end
  end
end
