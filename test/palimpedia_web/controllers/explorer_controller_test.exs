defmodule PalimpediaWeb.ExplorerControllerTest do
  use PalimpediaWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "GET /explore" do
    test "renders the home page with search and stats", %{conn: conn} do
      conn = get(conn, "/explore")
      body = html_response(conn, 200)

      assert body =~ "Palimpedia"
      assert body =~ "Search the knowledge graph"
      assert body =~ "2 nodes"
      assert body =~ "1 edges"
    end

    test "renders search results when q is provided", %{conn: conn} do
      conn = get(conn, "/explore?q=Quantum")
      body = html_response(conn, 200)

      assert body =~ "Quantum Mechanics"
      assert body =~ "Quantum Entanglement"
      assert body =~ ~r/href="\/explore\/nodes\/\d+"/
    end

    test "shows empty message for no results", %{conn: conn} do
      conn = get(conn, "/explore?q=nonexistent_xyz")
      body = html_response(conn, 200)

      assert body =~ "No results"
    end
  end

  describe "GET /explore/nodes/:id" do
    test "renders an anchor node with confidence and edges", %{conn: conn} do
      conn = get(conn, "/explore/nodes/1")
      body = html_response(conn, 200)

      assert body =~ "Quantum Mechanics"
      assert body =~ "anchor"
      assert body =~ "confidence"
      assert body =~ "0 hops from anchor"
      # Should show linked neighbor
      assert body =~ "Quantum Entanglement"
      # Should have a hyperlink to the neighbor
      assert body =~ ~r/href="\/explore\/nodes\/2"/
    end

    test "renders a generated node with generated_at", %{conn: conn} do
      conn = get(conn, "/explore/nodes/2")
      body = html_response(conn, 200)

      assert body =~ "Quantum Entanglement"
      assert body =~ "generated"
      assert body =~ "1 hops from anchor"
    end

    test "returns 404 for unknown node", %{conn: conn} do
      conn = get(conn, "/explore/nodes/999")
      body = html_response(conn, 404)

      assert body =~ "Not Found"
    end

    test "returns 400 for non-integer ID", %{conn: conn} do
      conn = get(conn, "/explore/nodes/abc")
      body = html_response(conn, 400)

      assert body =~ "Invalid"
    end
  end

  describe "GET /explore/random" do
    test "redirects to a node page", %{conn: conn} do
      conn = get(conn, "/explore/random")
      assert redirected_to(conn) =~ ~r/\/explore\/nodes\/\d+/
    end
  end
end
