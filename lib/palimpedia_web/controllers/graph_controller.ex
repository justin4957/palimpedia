defmodule PalimpediaWeb.GraphController do
  use PalimpediaWeb, :controller

  alias PalimpediaWeb.GraphJSON

  @moduledoc """
  REST API for graph-level operations.
  Subgraph retrieval, coverage maps, and system status.
  """

  @doc "GET /api/graph/subgraph/:id?hops=N — Local subgraph neighborhood."
  def subgraph(conn, %{"id" => node_id_str} = params) do
    hops = params |> Map.get("hops", "2") |> parse_int(2) |> min(5)

    case Integer.parse(node_id_str) do
      {node_id, ""} ->
        case graph_repo().subgraph(node_id, hops) do
          {:ok, nodes, edges} ->
            json(conn, %{
              data: %{
                nodes: GraphJSON.nodes_to_json(nodes),
                edges: GraphJSON.edges_to_json(edges)
              },
              meta: %{
                center_node_id: node_id,
                hops: hops,
                node_count: length(nodes),
                edge_count: length(edges)
              }
            })

          {:error, :not_found} ->
            conn |> put_status(404) |> json(%{error: "Node not found", node_id: node_id})

          {:error, reason} ->
            conn
            |> put_status(500)
            |> json(%{error: "Subgraph query failed", detail: inspect(reason)})
        end

      _ ->
        conn |> put_status(400) |> json(%{error: "Invalid node ID, must be an integer"})
    end
  end

  @doc "GET /api/graph/stats — Graph-level statistics and coverage."
  def stats(conn, _params) do
    case graph_repo().stats() do
      {:ok, graph_stats} ->
        json(conn, %{data: graph_stats})

      {:error, reason} ->
        conn |> put_status(500) |> json(%{error: "Stats query failed", detail: inspect(reason)})
    end
  end

  @doc "GET /api/graph/gaps — Current structural gaps detected."
  def gaps(conn, _params) do
    case graph_repo().find_orphans(limit: 50) do
      {:ok, orphans} ->
        json(conn, %{
          data: %{
            orphan_nodes: GraphJSON.nodes_to_json(orphans)
          },
          meta: %{orphan_count: length(orphans)}
        })

      {:error, reason} ->
        conn |> put_status(500) |> json(%{error: "Gap detection failed", detail: inspect(reason)})
    end
  end

  # --- Private ---

  defp graph_repo do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp parse_int(n, _default) when is_integer(n), do: n
  defp parse_int(_, default), do: default
end
