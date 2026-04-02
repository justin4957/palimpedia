defmodule PalimpediaWeb.ProvenanceController do
  use PalimpediaWeb, :controller

  alias Palimpedia.Confidence.ProvenanceExplorer

  @moduledoc """
  REST API for provenance tracing, auditing, and broken chain detection.
  """

  @doc "GET /api/provenance/trace/:node_id — Trace provenance for a node."
  def trace(conn, %{"node_id" => node_id_str}) do
    case Integer.parse(node_id_str) do
      {node_id, ""} ->
        case ProvenanceExplorer.trace_node(node_id) do
          {:ok, result} ->
            json(conn, %{data: result})

          {:error, :not_found} ->
            conn |> put_status(404) |> json(%{error: "Node not found"})

          {:error, reason} ->
            conn |> put_status(500) |> json(%{error: inspect(reason)})
        end

      _ ->
        conn |> put_status(400) |> json(%{error: "Invalid node ID"})
    end
  end

  @doc "GET /api/provenance/audit — Full provenance audit."
  def audit(conn, _params) do
    case ProvenanceExplorer.audit() do
      {:ok, result} ->
        json(conn, %{
          data: %{
            total_nodes: result.total_nodes,
            traceable_nodes: result.traceable_nodes,
            traceability_rate: result.traceability_rate,
            broken_chain_count: length(result.broken_chains),
            citation_loop_count: length(result.citation_loops),
            passes_audit: result.passes_audit,
            target: "90% traceability"
          }
        })

      {:error, reason} ->
        conn |> put_status(500) |> json(%{error: inspect(reason)})
    end
  end

  @doc "GET /api/provenance/broken-chains — Nodes with broken provenance."
  def broken_chains(conn, _params) do
    case ProvenanceExplorer.find_broken_chains() do
      {:ok, broken} ->
        json(conn, %{
          data: broken,
          meta: %{count: length(broken)}
        })

      {:error, reason} ->
        conn |> put_status(500) |> json(%{error: inspect(reason)})
    end
  end
end
