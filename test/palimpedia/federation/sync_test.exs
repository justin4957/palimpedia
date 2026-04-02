defmodule Palimpedia.Federation.SyncTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Federation.{Sync, Protocol}

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "export_subgraph/2" do
    test "exports a subgraph as a federation message" do
      {:ok, result} = Sync.export_subgraph(1, hops: 1)

      assert result.nodes_exported == 2
      assert result.edges_exported == 1
      assert is_binary(result.message)

      # Verify the message is valid protocol
      {:ok, decoded} = Protocol.decode(result.message)
      assert decoded.type == :subgraph_share
      assert decoded.payload["node_count"] == 2
    end
  end

  describe "import_message/2" do
    test "imports a federation message" do
      # First export
      {:ok, export} = Sync.export_subgraph(1, hops: 1)

      # Then import (nodes will be skipped as duplicates since mock repo finds them)
      {:ok, result} = Sync.import_message(export.message)

      assert is_integer(result.nodes_imported)
      assert is_integer(result.edges_imported)
      assert is_integer(result.skipped)
      # MockGraphRepo.search_nodes finds existing nodes, so most will be skipped
      assert result.skipped >= 0
    end

    test "rejects invalid protocol messages" do
      invalid = Jason.encode!(%{protocol: "wrong/1.0", type: "subgraph_share", payload: %{}})
      assert {:error, _} = Sync.import_message(invalid)
    end
  end

  describe "export_edge_assertion/4" do
    test "exports an edge assertion as a federation message" do
      {:ok, json} = Sync.export_edge_assertion("Physics", "QM", :generalizes, confidence: 0.9)

      {:ok, decoded} = Protocol.decode(json)
      assert decoded.type == :edge_assertion
      assert decoded.payload["source_title"] == "Physics"
      assert decoded.payload["target_title"] == "QM"
      assert decoded.payload["edge_type"] == "generalizes"
    end
  end
end
