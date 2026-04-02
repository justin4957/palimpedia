defmodule PalimpediaWeb.CoverageController do
  use PalimpediaWeb, :controller

  alias Palimpedia.Coverage.Map, as: CoverageMap

  @moduledoc """
  REST API for coverage maps, confidence distribution,
  blind spot reporting, and the epistemic gap index.
  """

  @doc "GET /api/coverage — Full coverage report."
  def index(conn, _params) do
    case CoverageMap.generate_report() do
      {:ok, report} ->
        conn
        |> put_resp_header("cache-control", "public, max-age=300")
        |> json(%{
          data: %{
            density: report.density,
            confidence_distribution: report.confidence_distribution,
            blind_spots: report.blind_spots,
            epistemic_index: report.epistemic_index,
            known_gaps_count: length(report.known_gaps)
          },
          generated_at: DateTime.to_iso8601(report.generated_at)
        })
    end
  end

  @doc "GET /api/coverage/density — Graph density by node type."
  def density(conn, _params) do
    graph_repo =
      Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)

    json(conn, %{data: CoverageMap.compute_density(graph_repo)})
  end

  @doc "GET /api/coverage/confidence — Confidence score distribution."
  def confidence(conn, _params) do
    graph_repo =
      Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)

    json(conn, %{data: CoverageMap.compute_confidence_distribution(graph_repo)})
  end

  @doc "GET /api/coverage/blind-spots — Known blind spots."
  def blind_spots(conn, _params) do
    graph_repo =
      Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)

    density = CoverageMap.compute_density(graph_repo)
    spots = CoverageMap.detect_blind_spots(density)

    json(conn, %{
      data: spots,
      meta: %{count: length(spots)}
    })
  end

  @doc "GET /api/coverage/gaps — Prioritized known gaps."
  def gaps(conn, params) do
    limit = Map.get(params, "limit", "50") |> String.to_integer()
    gaps = CoverageMap.fetch_known_gaps(limit: limit)

    json(conn, %{
      data: gaps,
      meta: %{count: length(gaps)}
    })
  end

  @doc "GET /api/coverage/epistemic-index — What the system cannot represent."
  def epistemic_index(conn, _params) do
    case CoverageMap.generate_report() do
      {:ok, report} ->
        json(conn, %{data: report.epistemic_index})
    end
  end
end
