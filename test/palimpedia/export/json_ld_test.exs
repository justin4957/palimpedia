defmodule Palimpedia.Export.JsonLDTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Export.JsonLD
  alias Palimpedia.Graph.{Node, Edge}

  @anchor %Node{
    id: 1,
    title: "Physics",
    content: "Science",
    node_type: :anchor,
    confidence: 1.0,
    provenance: ["wikidata:Q413"]
  }
  @generated %Node{
    id: 2,
    title: "QM",
    content: "Quantum",
    node_type: :generated,
    confidence: 0.8,
    anchor_distance: 1,
    provenance: []
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
    test "produces valid JSON-LD with @context and @graph" do
      output = JsonLD.export([@anchor, @generated], [@edge])
      {:ok, parsed} = Jason.decode(output)

      assert Map.has_key?(parsed, "@context")
      assert Map.has_key?(parsed, "@graph")
      assert length(parsed["@graph"]) == 2
    end

    test "@context includes schema.org and palimpedia vocabulary" do
      output = JsonLD.export([@anchor], [])
      {:ok, parsed} = Jason.decode(output)

      context = parsed["@context"]
      assert context["@vocab"] == "http://schema.org/"
      assert context["palimpedia"] == "https://palimpedia.org/ontology/"
    end

    test "nodes have @id, @type, name, and confidence" do
      output = JsonLD.export([@anchor], [])
      {:ok, parsed} = Jason.decode(output)

      [node] = parsed["@graph"]
      assert node["@id"] =~ "node/1"
      assert node["@type"] == "Article"
      assert node["name"] == "Physics"
      assert node["confidence"] == 1.0
    end

    test "edges included as relationships on source node" do
      output = JsonLD.export([@anchor, @generated], [@edge])
      {:ok, parsed} = Jason.decode(output)

      physics = Enum.find(parsed["@graph"], &(&1["name"] == "Physics"))
      assert Map.has_key?(physics, "palimpedia:relationships")

      [rel] = physics["palimpedia:relationships"]
      assert rel["target"] =~ "node/2"
      assert rel["confidence"] == 0.9
    end
  end
end
