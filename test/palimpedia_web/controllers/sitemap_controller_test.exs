defmodule PalimpediaWeb.SitemapControllerTest do
  use PalimpediaWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "GET /sitemap.xml" do
    test "returns valid XML with document URLs", %{conn: conn} do
      conn = conn |> put_req_header("accept", "application/xml") |> get("/sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "<?xml version")
      assert String.contains?(body, "<urlset")
      assert String.contains?(body, "/explore/nodes/")
      assert String.contains?(body, "<priority>")
      assert String.contains?(body, "<changefreq>")
    end

    test "includes the explore home page", %{conn: conn} do
      conn = conn |> put_req_header("accept", "application/xml") |> get("/sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "/explore</loc>")
      assert String.contains?(body, "<priority>1.0</priority>")
    end

    test "sets cache headers", %{conn: conn} do
      conn = conn |> put_req_header("accept", "application/xml") |> get("/sitemap.xml")
      assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
    end

    test "sets XML content type", %{conn: conn} do
      conn = conn |> put_req_header("accept", "application/xml") |> get("/sitemap.xml")
      assert get_resp_header(conn, "content-type") |> hd() |> String.contains?("xml")
    end
  end
end
