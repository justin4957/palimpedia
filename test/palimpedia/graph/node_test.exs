defmodule Palimpedia.Graph.NodeTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Graph.Node

  describe "new_anchor/3" do
    test "creates an anchor node with max confidence" do
      node = Node.new_anchor("Test Node", "Content here", "wikidata:Q123")

      assert node.title == "Test Node"
      assert node.content == "Content here"
      assert node.node_type == :anchor
      assert node.confidence == 1.0
      assert node.anchor_distance == 0
      assert node.provenance == ["wikidata:Q123"]
    end
  end

  describe "new_generated/3" do
    test "creates a generated node with provided confidence" do
      node =
        Node.new_generated("Bridge Doc", "Generated content",
          confidence: 0.7,
          provenance: ["wikidata:Q123", "wikidata:Q456"],
          anchor_distance: 2
        )

      assert node.title == "Bridge Doc"
      assert node.node_type == :generated
      assert node.confidence == 0.7
      assert node.anchor_distance == 2
      assert node.generated_at != nil
    end

    test "defaults to zero confidence when not provided" do
      node = Node.new_generated("Sparse Doc", "Thin content")

      assert node.confidence == 0.0
      assert node.provenance == []
    end
  end

  describe "new_request/1" do
    test "creates a request node placeholder" do
      node = Node.new_request("Requested Topic")

      assert node.title == "Requested Topic"
      assert node.node_type == :requested
      assert node.confidence == 0.0
      assert node.content == nil
    end
  end
end
