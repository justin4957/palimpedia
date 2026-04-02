defmodule PalimpediaWeb.OnDemandControllerTest do
  use PalimpediaWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "GET /api/generate/evaluate" do
    test "returns existing node when found", %{conn: conn} do
      conn = get(conn, "/api/generate/evaluate?title=Quantum Mechanics")
      response = json_response(conn, 200)

      assert response["status"] == "exists"
      assert response["data"]["title"] == "Quantum Mechanics"
    end

    test "declines unknown titles with low pressure", %{conn: conn} do
      conn = get(conn, "/api/generate/evaluate?title=Completely Unknown XYZ")
      response = json_response(conn, 200)

      assert response["status"] == "declined"
      assert response["message"] =~ "Insufficient structural pressure"
    end

    test "returns 400 when title is missing", %{conn: conn} do
      conn = get(conn, "/api/generate/evaluate")
      assert json_response(conn, 400)["error"] =~ "title"
    end
  end

  describe "GET /api/generate/status" do
    test "returns unknown for untracked titles", %{conn: conn} do
      conn = get(conn, "/api/generate/status?title=Never Requested")
      assert json_response(conn, 404)["status"] == "unknown"
    end

    test "returns status after evaluation", %{conn: conn} do
      # First evaluate
      get(conn, "/api/generate/evaluate?title=Some Unknown Title ABC")

      # Then check status
      conn = get(conn, "/api/generate/status?title=Some Unknown Title ABC")
      response = json_response(conn, 200)
      assert response["status"] in ["declined", "enqueued"]
    end

    test "returns 400 when title is missing", %{conn: conn} do
      conn = get(conn, "/api/generate/status")
      assert json_response(conn, 400)
    end
  end

  describe "GET /api/generate/pending" do
    test "returns list of pending requests", %{conn: conn} do
      conn = get(conn, "/api/generate/pending")
      response = json_response(conn, 200)

      assert is_list(response["data"])
      assert is_integer(response["meta"]["count"])
    end
  end
end
