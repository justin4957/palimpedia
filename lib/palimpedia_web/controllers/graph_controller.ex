defmodule PalimpediaWeb.GraphController do
  use PalimpediaWeb, :controller

  @moduledoc """
  REST API for graph-level operations.
  Subgraph retrieval, coverage maps, and system status.
  """

  @doc "GET /api/graph/subgraph/:id?hops=N — Local subgraph neighborhood."
  def subgraph(conn, %{"id" => node_id} = params) do
    hops = Map.get(params, "hops", "2") |> String.to_integer()

    json(conn, %{
      status: "scaffold",
      message: "Subgraph retrieval not yet implemented",
      node_id: node_id,
      hops: hops
    })
  end

  @doc "GET /api/graph/stats — Graph-level statistics and coverage."
  def stats(conn, _params) do
    json(conn, %{
      status: "scaffold",
      total_nodes: 0,
      total_edges: 0,
      anchor_nodes: 0,
      generated_nodes: 0,
      pending_generation: 0,
      open_contradictions: 0
    })
  end

  @doc "GET /api/graph/gaps — Current structural gaps detected."
  def gaps(conn, _params) do
    json(conn, %{
      status: "scaffold",
      message: "Gap detection not yet implemented",
      gaps: []
    })
  end
end
