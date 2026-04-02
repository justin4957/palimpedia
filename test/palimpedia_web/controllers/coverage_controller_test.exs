defmodule PalimpediaWeb.CoverageControllerTest do
  use PalimpediaWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "GET /api/coverage" do
    test "returns full coverage report", %{conn: conn} do
      conn = get(conn, "/api/coverage")
      assert %{"data" => data} = json_response(conn, 200)

      assert Map.has_key?(data, "density")
      assert Map.has_key?(data, "confidence_distribution")
      assert Map.has_key?(data, "blind_spots")
      assert Map.has_key?(data, "epistemic_index")
    end
  end

  describe "GET /api/coverage/density" do
    test "returns density by type", %{conn: conn} do
      conn = get(conn, "/api/coverage/density")
      assert %{"data" => data} = json_response(conn, 200)

      assert data["total_nodes"] > 0
      assert Map.has_key?(data, "by_type")
    end
  end

  describe "GET /api/coverage/confidence" do
    test "returns confidence histogram", %{conn: conn} do
      conn = get(conn, "/api/coverage/confidence")
      assert %{"data" => data} = json_response(conn, 200)

      assert Map.has_key?(data, "histogram")
      assert Map.has_key?(data, "avg_confidence")
    end
  end

  describe "GET /api/coverage/blind-spots" do
    test "returns blind spots with severity", %{conn: conn} do
      conn = get(conn, "/api/coverage/blind-spots")
      assert %{"data" => data, "meta" => meta} = json_response(conn, 200)

      assert is_list(data)
      assert is_integer(meta["count"])
    end
  end

  describe "GET /api/coverage/epistemic-index" do
    test "returns the epistemic limitation index", %{conn: conn} do
      conn = get(conn, "/api/coverage/epistemic-index")
      assert %{"data" => data} = json_response(conn, 200)

      assert Map.has_key?(data, "coverage_score")
      assert Map.has_key?(data, "summary")
      assert Map.has_key?(data, "blind_spot_count")
    end
  end
end
