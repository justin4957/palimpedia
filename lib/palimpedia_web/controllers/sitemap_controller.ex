defmodule PalimpediaWeb.SitemapController do
  use PalimpediaWeb, :controller

  @moduledoc """
  Generates sitemap.xml for search engine crawlers.
  Lists all public document nodes with last-modified dates.
  """

  @doc "GET /sitemap.xml — XML sitemap of all document nodes."
  def index(conn, _params) do
    nodes = fetch_all_nodes()
    host = PalimpediaWeb.Endpoint.url()

    xml = build_sitemap_xml(nodes, host)

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, xml)
  end

  defp fetch_all_nodes do
    graph_repo =
      Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)

    case graph_repo.search_nodes("", limit: 50_000) do
      {:ok, nodes} -> nodes
      _ -> []
    end
  end

  defp build_sitemap_xml(nodes, host) do
    urls =
      Enum.map(nodes, fn node ->
        loc = "#{host}/explore/nodes/#{node.id}"

        lastmod =
          if node.generated_at do
            DateTime.to_date(node.generated_at) |> Date.to_iso8601()
          else
            Date.utc_today() |> Date.to_iso8601()
          end

        priority =
          cond do
            node.node_type == :anchor -> "0.8"
            node.confidence >= 0.7 -> "0.6"
            true -> "0.4"
          end

        """
          <url>
            <loc>#{escape_xml(loc)}</loc>
            <lastmod>#{lastmod}</lastmod>
            <changefreq>weekly</changefreq>
            <priority>#{priority}</priority>
          </url>
        """
      end)
      |> Enum.join()

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <url>
        <loc>#{escape_xml(host)}/explore</loc>
        <changefreq>daily</changefreq>
        <priority>1.0</priority>
      </url>
    #{urls}</urlset>
    """
  end

  defp escape_xml(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
