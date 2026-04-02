defmodule PalimpediaWeb.BiasAuditControllerTest do
  use PalimpediaWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "GET /api/coverage/bias-audit" do
    test "returns bias audit results", %{conn: conn} do
      conn = get(conn, "/api/coverage/bias-audit")
      assert %{"data" => data} = json_response(conn, 200)

      assert is_list(data["domain_coverage"])
      assert is_list(data["underrepresented"])
      assert is_float(data["coverage_balance_score"])
      assert is_list(data["recommendations"])
    end
  end

  describe "GET /api/coverage/taxonomy" do
    test "returns reference taxonomy", %{conn: conn} do
      conn = get(conn, "/api/coverage/taxonomy")
      assert %{"data" => data} = json_response(conn, 200)

      assert is_list(data)
      assert length(data) > 0

      [first | _] = data
      assert Map.has_key?(first, "domain")
      assert Map.has_key?(first, "expected_share")
      assert Map.has_key?(first, "keywords")
    end
  end
end
