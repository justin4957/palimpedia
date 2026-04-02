defmodule PalimpediaWeb.FederationControllerTest do
  use PalimpediaWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "GET /api/federation/peers" do
    test "lists peers with local instance ID", %{conn: conn} do
      conn = get(conn, "/api/federation/peers")
      assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

      assert is_list(data)
      assert is_binary(meta["local_instance"])
    end
  end

  describe "POST /api/federation/peers" do
    test "registers a new peer", %{conn: conn} do
      conn =
        post(conn, "/api/federation/peers", %{
          "instance_id" => "peer-001",
          "url" => "https://peer1.palimpedia.org",
          "name" => "Peer 1"
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["instance_id"] == "peer-001"
      assert data["trust_level"] == "untrusted"
    end

    test "returns 400 for missing fields", %{conn: conn} do
      conn = post(conn, "/api/federation/peers", %{})
      assert json_response(conn, 400)
    end
  end

  describe "POST /api/federation/export/:node_id" do
    test "exports a subgraph", %{conn: conn} do
      conn = post(conn, "/api/federation/export/1", %{"hops" => "1"})
      assert %{"data" => data, "message" => message} = json_response(conn, 200)

      assert data["nodes_exported"] == 2
      assert data["edges_exported"] == 1
      assert is_binary(message)
    end
  end

  describe "POST /api/federation/import" do
    test "imports a federation message", %{conn: conn} do
      # First export
      export_conn = post(conn, "/api/federation/export/1")
      %{"message" => message} = json_response(export_conn, 200)

      # Then import
      import_conn = post(conn, "/api/federation/import", %{"message" => message})
      assert %{"data" => data} = json_response(import_conn, 200)

      assert is_integer(data["nodes_imported"])
      assert is_integer(data["edges_imported"])
    end
  end
end
