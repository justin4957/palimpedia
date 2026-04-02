defmodule Palimpedia.Export.RDFTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Export.RDF
  alias Palimpedia.Graph.{Node, Edge}

  @anchor %Node{
    id: 1,
    title: "Physics",
    content: "Science of matter",
    node_type: :anchor,
    confidence: 1.0,
    anchor_distance: 0,
    provenance: ["wikidata:Q413"]
  }
  @generated %Node{
    id: 2,
    title: "Quantum Mechanics",
    content: "Subfield",
    node_type: :generated,
    confidence: 0.8,
    anchor_distance: 1,
    provenance: ["wikidata:Q944"],
    generated_at: ~U[2026-01-15 12:00:00Z]
  }
  @edge %Edge{
    id: 100,
    source_id: 1,
    target_id: 2,
    edge_type: :generalizes,
    confidence: 0.9,
    provenance: []
  }

  describe "export/2" do
    test "produces valid N-Triples" do
      output = RDF.export([@anchor, @generated], [@edge])

      assert String.contains?(output, "<https://palimpedia.org/resource/node/1>")
      assert String.contains?(output, "<http://schema.org/name>")
      assert String.contains?(output, "\"Physics\"")
      assert String.contains?(output, "<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>")
      assert String.contains?(output, "<http://schema.org/Article>")
    end

    test "includes edge triples" do
      output = RDF.export([@anchor, @generated], [@edge])

      assert String.contains?(output, "<https://palimpedia.org/ontology/generalizes>")
      assert String.contains?(output, "node/2>")
    end

    test "includes confidence and anchor distance" do
      output = RDF.export([@anchor], [])

      assert String.contains?(output, "confidence")
      assert String.contains?(output, "anchorDistance")
    end

    test "includes provenance identifiers" do
      output = RDF.export([@anchor], [])
      assert String.contains?(output, "wikidata:Q413")
    end

    test "every line ends with period (N-Triples format)" do
      output = RDF.export([@anchor, @generated], [@edge])

      for line <- String.split(output, "\n"), line != "" do
        assert String.ends_with?(line, " .")
      end
    end
  end
end
