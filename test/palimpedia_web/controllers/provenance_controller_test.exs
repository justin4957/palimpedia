defmodule PalimpediaWeb.ProvenanceControllerTest do
  use PalimpediaWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "GET /api/provenance/trace/:node_id" do
    test "returns provenance trace for a node", %{conn: conn} do
      conn = get(conn, "/api/provenance/trace/1")
      assert %{"data" => data} = json_response(conn, 200)

      assert data["node_id"] == 1
      assert data["grounded"] == true
      assert is_list(data["provenance_path"])
      assert is_list(data["anchor_sources"])
    end

    test "returns 404 for unknown node", %{conn: conn} do
      conn = get(conn, "/api/provenance/trace/999")
      assert json_response(conn, 404)
    end

    test "returns 400 for invalid ID", %{conn: conn} do
      conn = get(conn, "/api/provenance/trace/abc")
      assert json_response(conn, 400)
    end
  end

  describe "GET /api/provenance/audit" do
    test "returns audit results with traceability rate", %{conn: conn} do
      conn = get(conn, "/api/provenance/audit")
      assert %{"data" => data} = json_response(conn, 200)

      assert Map.has_key?(data, "traceability_rate")
      assert Map.has_key?(data, "passes_audit")
      assert Map.has_key?(data, "broken_chain_count")
      assert data["target"] == "90% traceability"
    end
  end

  describe "GET /api/provenance/broken-chains" do
    test "returns broken chain nodes", %{conn: conn} do
      conn = get(conn, "/api/provenance/broken-chains")
      assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

      assert is_list(data)
      assert is_integer(meta["count"])
    end
  end
end
