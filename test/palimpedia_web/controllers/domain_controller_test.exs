defmodule PalimpediaWeb.DomainControllerTest do
  use PalimpediaWeb.ConnCase, async: false

  describe "GET /api/domains" do
    test "lists all domain profiles", %{conn: conn} do
      conn = get(conn, "/api/domains")
      assert %{"data" => domains, "meta" => meta} = json_response(conn, 200)

      assert length(domains) == 3
      assert meta["count"] == 3
      ids = Enum.map(domains, & &1["id"])
      assert "general" in ids
      assert "legal" in ids
      assert "scientific" in ids
    end

    test "shows active domain", %{conn: conn} do
      conn = get(conn, "/api/domains")
      assert %{"meta" => %{"active" => active}} = json_response(conn, 200)
      assert active in ["general", "legal", "scientific"]
    end
  end

  describe "GET /api/domains/:id" do
    test "returns legal profile with edge types", %{conn: conn} do
      conn = get(conn, "/api/domains/legal")
      assert %{"data" => data} = json_response(conn, 200)

      assert data["id"] == "legal"
      assert "amends" in data["edge_types"]
      assert is_list(data["all_edge_types"])
      assert length(data["all_edge_types"]) > length(data["edge_types"])
    end

    test "returns scientific profile", %{conn: conn} do
      conn = get(conn, "/api/domains/scientific")
      assert %{"data" => data} = json_response(conn, 200)

      assert data["id"] == "scientific"
      assert "cites" in data["edge_types"]
    end

    test "returns 404 for unknown domain", %{conn: conn} do
      conn = get(conn, "/api/domains/nonexistent")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/domains/:id/edge-types" do
    test "returns base and domain-specific types", %{conn: conn} do
      conn = get(conn, "/api/domains/legal/edge-types")
      assert %{"data" => data} = json_response(conn, 200)

      assert is_list(data["base_types"])
      assert is_list(data["domain_types"])
      assert is_list(data["all_types"])
      assert "references" in data["base_types"]
      assert "amends" in data["domain_types"]
    end
  end
end
