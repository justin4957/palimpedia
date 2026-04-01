defmodule PalimpediaWeb.GraphControllerTest do
  use PalimpediaWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "GET /api/graph/subgraph/:id" do
    test "returns nodes and edges for a subgraph", %{conn: conn} do
      conn = get(conn, "/api/graph/subgraph/1?hops=2")
      assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

      assert length(data["nodes"]) == 2
      assert length(data["edges"]) == 1
      assert meta["center_node_id"] == 1
      assert meta["hops"] == 2
      assert meta["node_count"] == 2
      assert meta["edge_count"] == 1

      # Verify node structure includes confidence envelope
      [first_node | _] = data["nodes"]
      assert Map.has_key?(first_node, "confidence")
      assert Map.has_key?(first_node["confidence"], "score")
      assert Map.has_key?(first_node["confidence"], "anchor_distance")
      assert Map.has_key?(first_node["confidence"], "requires_regrounding")
    end

    test "returns subgraph for isolated node", %{conn: conn} do
      conn = get(conn, "/api/graph/subgraph/2")
      assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

      assert length(data["nodes"]) == 1
      assert data["edges"] == []
      assert meta["node_count"] == 1
    end

    test "returns 404 for unknown node", %{conn: conn} do
      conn = get(conn, "/api/graph/subgraph/999")
      assert %{"error" => "Node not found"} = json_response(conn, 404)
    end

    test "returns 400 for non-integer ID", %{conn: conn} do
      conn = get(conn, "/api/graph/subgraph/abc")
      assert %{"error" => _} = json_response(conn, 400)
    end

    test "caps hops at 5", %{conn: conn} do
      conn = get(conn, "/api/graph/subgraph/1?hops=100")
      assert %{"meta" => %{"hops" => 5}} = json_response(conn, 200)
    end
  end

  describe "GET /api/graph/stats" do
    test "returns graph statistics", %{conn: conn} do
      conn = get(conn, "/api/graph/stats")
      assert %{"data" => data} = json_response(conn, 200)

      assert data["total_nodes"] == 2
      assert data["total_edges"] == 1
      assert data["anchor_nodes"] == 1
      assert data["generated_nodes"] == 1
      assert data["avg_confidence"] == 0.875
    end
  end

  describe "GET /api/graph/gaps" do
    test "returns orphan nodes as gap indicators", %{conn: conn} do
      conn = get(conn, "/api/graph/gaps")
      assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

      assert is_list(data["orphan_nodes"])
      assert is_integer(meta["orphan_count"])
    end
  end
end
