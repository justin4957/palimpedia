defmodule PalimpediaWeb.GraphQL.SchemaTest do
  use PalimpediaWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  defp graphql(conn, query) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/graphql", Jason.encode!(%{query: query}))
  end

  describe "node query" do
    test "fetches a node by ID with confidence envelope", %{conn: conn} do
      conn = graphql(conn, """
        { node(id: 1) { id title nodeType confidence { score anchorDistance requiresRegrounding } provenance } }
      """)

      assert %{"data" => %{"node" => node}} = json_response(conn, 200)
      assert node["id"] == 1
      assert node["title"] == "Quantum Mechanics"
      assert node["nodeType"] == "anchor"
      assert node["confidence"]["score"] == 1.0
      assert node["confidence"]["anchorDistance"] == 0
      assert node["confidence"]["requiresRegrounding"] == false
      assert is_list(node["provenance"])
    end

    test "returns error for unknown node", %{conn: conn} do
      conn = graphql(conn, "{ node(id: 999) { id title } }")
      assert %{"errors" => [error]} = json_response(conn, 200)
      assert error["message"] =~ "not found"
    end
  end

  describe "nodes query" do
    test "searches nodes by title", %{conn: conn} do
      conn = graphql(conn, """
        { nodes(query: "Quantum", limit: 10) { id title nodeType confidence { score } } }
      """)

      assert %{"data" => %{"nodes" => nodes}} = json_response(conn, 200)
      assert length(nodes) > 0
      assert Enum.all?(nodes, &Map.has_key?(&1, "confidence"))
    end

    test "returns empty list for no matches", %{conn: conn} do
      conn = graphql(conn, ~s|{ nodes(query: "nonexistent_xyz") { id } }|)
      assert %{"data" => %{"nodes" => []}} = json_response(conn, 200)
    end
  end

  describe "subgraph query" do
    test "returns nodes and edges for a neighborhood", %{conn: conn} do
      conn = graphql(conn, """
        { subgraph(nodeId: 1, hops: 2) {
          centerNodeId hops
          nodes { id title confidence { score } }
          edges { id sourceId targetId edgeType confidence }
        } }
      """)

      assert %{"data" => %{"subgraph" => sg}} = json_response(conn, 200)
      assert sg["centerNodeId"] == 1
      assert sg["hops"] == 2
      assert length(sg["nodes"]) == 2
      assert length(sg["edges"]) == 1
    end
  end

  describe "stats query" do
    test "returns graph statistics", %{conn: conn} do
      conn = graphql(conn, """
        { stats { totalNodes totalEdges anchorNodes generatedNodes avgConfidence } }
      """)

      assert %{"data" => %{"stats" => stats}} = json_response(conn, 200)
      assert stats["totalNodes"] == 2
      assert stats["totalEdges"] == 1
    end
  end

  describe "contradictions query" do
    test "returns open contradictions", %{conn: conn} do
      conn = graphql(conn, """
        { contradictions { id nodeAId nodeBId description severity status } }
      """)

      assert %{"data" => %{"contradictions" => list}} = json_response(conn, 200)
      assert is_list(list)
    end
  end

  describe "generationQueue query" do
    test "returns queue entries", %{conn: conn} do
      conn = graphql(conn, """
        { generationQueue { id gapType priority suggestedTitle status demandCount } }
      """)

      assert %{"data" => %{"generationQueue" => list}} = json_response(conn, 200)
      assert is_list(list)
    end
  end
end
