defmodule Palimpedia.Federation.ProtocolTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Federation.Protocol
  alias Palimpedia.Graph.{Node, Edge}

  describe "encode/3 and decode/1" do
    test "round-trips a message" do
      {:ok, json} = Protocol.encode(:subgraph_share, %{test: true}, "instance-1")
      {:ok, decoded} = Protocol.decode(json)

      assert decoded.type == :subgraph_share
      assert decoded.source_instance == "instance-1"
      assert decoded.protocol == Protocol.version()
      assert decoded.payload["test"] == true
    end

    test "rejects unknown protocol version" do
      json =
        Jason.encode!(%{
          protocol: "unknown/2.0",
          type: "subgraph_share",
          source_instance: "x",
          payload: %{}
        })

      assert {:error, {:unsupported_protocol, "unknown/2.0"}} = Protocol.decode(json)
    end

    test "rejects missing protocol" do
      json = Jason.encode!(%{type: "subgraph_share", source_instance: "x", payload: %{}})
      assert {:error, :missing_protocol} = Protocol.decode(json)
    end
  end

  describe "serialize_subgraph/2" do
    test "serializes nodes and edges" do
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
          title: "QM",
          node_type: :generated,
          confidence: 0.8,
          provenance: ["wikidata:Q944"]
        }
      ]

      edges = [
        %Edge{
          id: 100,
          source_id: 1,
          target_id: 2,
          edge_type: :generalizes,
          confidence: 0.9,
          provenance: []
        }
      ]

      payload = Protocol.serialize_subgraph(nodes, edges)

      assert payload.node_count == 2
      assert payload.edge_count == 1
      assert length(payload.nodes) == 2
      assert hd(payload.nodes).title == "Physics"
      assert hd(payload.edges).source_title == "Physics"
      assert hd(payload.edges).target_title == "QM"
    end
  end

  describe "deserialize_subgraph/1" do
    test "deserializes back to structs" do
      payload = %{
        "nodes" => [
          %{
            "title" => "Physics",
            "node_type" => "anchor",
            "confidence" => 1.0,
            "provenance" => ["wikidata:Q413"]
          },
          %{"title" => "QM", "node_type" => "generated", "confidence" => 0.8, "provenance" => []}
        ],
        "edges" => [
          %{
            "source_title" => "Physics",
            "target_title" => "QM",
            "edge_type" => "generalizes",
            "confidence" => 0.9,
            "provenance" => []
          }
        ]
      }

      {:ok, nodes, edges} = Protocol.deserialize_subgraph(payload)

      assert length(nodes) == 2
      assert hd(nodes).title == "Physics"
      assert hd(nodes).node_type == :anchor
      assert length(edges) == 1
      assert hd(edges).edge_type == :generalizes
    end
  end
end
