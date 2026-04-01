defmodule PalimpediaWeb.NodeController do
  use PalimpediaWeb, :controller

  @moduledoc """
  REST API for graph nodes (documents).
  Supports retrieval, search, and the three tiers of user interaction.
  """

  @doc "GET /api/nodes/:id — Retrieve a document node with confidence metadata."
  def show(conn, %{"id" => node_id}) do
    # TODO: Wire to Graph.Repository
    json(conn, %{
      status: "scaffold",
      message: "Node retrieval not yet implemented",
      node_id: node_id
    })
  end

  @doc "GET /api/nodes/search?q=query — Search nodes by title/content."
  def search(conn, %{"q" => query_text}) do
    json(conn, %{
      status: "scaffold",
      message: "Search not yet implemented",
      query: query_text,
      results: []
    })
  end

  @doc "POST /api/nodes/request — Tier 1: Request generation of a new document."
  def request_node(conn, %{"title" => _title} = params) do
    json(conn, %{
      status: "scaffold",
      message: "Node request queued",
      tier: 1,
      params: params
    })
  end

  @doc "POST /api/edges — Tier 2: Assert an edge relationship."
  def assert_edge(conn, params) do
    json(conn, %{
      status: "scaffold",
      message: "Edge assertion received",
      tier: 2,
      params: params
    })
  end

  @doc "POST /api/contradictions — Tier 3: Flag a contradiction."
  def flag_contradiction(conn, params) do
    json(conn, %{
      status: "scaffold",
      message: "Contradiction flag received",
      tier: 3,
      params: params
    })
  end
end
