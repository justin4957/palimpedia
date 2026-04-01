defmodule PalimpediaWeb.NodeControllerTest do
  use PalimpediaWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "GET /api/nodes/:id" do
    test "returns a node with confidence envelope", %{conn: conn} do
      conn = get(conn, "/api/nodes/1")
      assert %{"data" => data} = json_response(conn, 200)

      assert data["id"] == 1
      assert data["title"] == "Quantum Mechanics"
      assert data["node_type"] == "anchor"
      assert data["confidence"]["score"] == 1.0
      assert data["confidence"]["anchor_distance"] == 0
      assert data["confidence"]["requires_regrounding"] == false
      assert is_list(data["provenance"])
    end

    test "returns a generated node with regrounding info", %{conn: conn} do
      conn = get(conn, "/api/nodes/2")
      assert %{"data" => data} = json_response(conn, 200)

      assert data["node_type"] == "generated"
      assert data["confidence"]["score"] == 0.75
      assert data["confidence"]["anchor_distance"] == 1
      assert data["generated_at"] != nil
    end

    test "returns 404 for unknown node", %{conn: conn} do
      conn = get(conn, "/api/nodes/999")
      assert %{"error" => "Node not found"} = json_response(conn, 404)
    end

    test "returns 400 for non-integer ID", %{conn: conn} do
      conn = get(conn, "/api/nodes/abc")
      assert %{"error" => _} = json_response(conn, 400)
    end
  end

  describe "GET /api/nodes/search" do
    test "returns matching nodes", %{conn: conn} do
      conn = get(conn, "/api/nodes/search?q=Quantum")
      assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

      assert length(data) == 2
      assert meta["query"] == "Quantum"
      assert meta["count"] == 2
    end

    test "returns empty list for no matches", %{conn: conn} do
      conn = get(conn, "/api/nodes/search?q=nonexistent")
      assert %{"data" => [], "meta" => %{"count" => 0}} = json_response(conn, 200)
    end

    test "respects limit parameter", %{conn: conn} do
      conn = get(conn, "/api/nodes/search?q=Quantum&limit=1")
      assert %{"data" => data, "meta" => %{"limit" => 1}} = json_response(conn, 200)
      assert length(data) == 1
    end

    test "returns 400 when q is missing", %{conn: conn} do
      conn = get(conn, "/api/nodes/search")
      assert %{"error" => _} = json_response(conn, 400)
    end
  end

  describe "POST /api/nodes/request" do
    test "creates a node request (Tier 1)", %{conn: conn} do
      conn =
        post(conn, "/api/nodes/request", %{"title" => "Dark Matter"})

      assert %{"data" => data, "meta" => meta} = json_response(conn, 201)
      assert data["title"] == "Dark Matter"
      assert data["node_type"] == "requested"
      assert data["confidence"]["score"] == 0.0
      assert meta["tier"] == 1
      assert meta["status"] == "queued"
    end

    test "returns 400 when title is missing", %{conn: conn} do
      conn = post(conn, "/api/nodes/request", %{})
      assert %{"error" => _} = json_response(conn, 400)
    end
  end

  describe "POST /api/edges" do
    test "creates an edge assertion (Tier 2)", %{conn: conn} do
      conn =
        post(conn, "/api/edges", %{
          "source_id" => "1",
          "target_id" => "2",
          "edge_type" => "references",
          "confidence" => 0.8
        })

      assert %{"data" => data, "meta" => meta} = json_response(conn, 201)
      assert data["edge_type"] == "references"
      assert data["confidence"] == 0.8
      assert meta["tier"] == 2
    end

    test "returns 400 for invalid edge type", %{conn: conn} do
      conn =
        post(conn, "/api/edges", %{
          "source_id" => "1",
          "target_id" => "2",
          "edge_type" => "bogus"
        })

      assert %{"error" => _} = json_response(conn, 400)
    end

    test "returns 400 for missing fields", %{conn: conn} do
      conn = post(conn, "/api/edges", %{})
      assert %{"error" => _} = json_response(conn, 400)
    end
  end

  describe "POST /api/contradictions" do
    test "flags a contradiction (Tier 3)", %{conn: conn} do
      conn =
        post(conn, "/api/contradictions", %{
          "node_a_id" => "1",
          "node_b_id" => "2",
          "description" => "Conflicting quantum interpretations"
        })

      assert %{"data" => data, "meta" => meta} = json_response(conn, 201)
      assert data["tier"] == 3
      assert data["node_a_id"] == 1
      assert data["node_b_id"] == 2
      assert data["description"] == "Conflicting quantum interpretations"
      assert meta["status"] == "flagged"
    end

    test "returns 400 for missing fields", %{conn: conn} do
      conn = post(conn, "/api/contradictions", %{"node_a_id" => "1"})
      assert %{"error" => _} = json_response(conn, 400)
    end
  end
end
