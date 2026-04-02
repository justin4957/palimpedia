defmodule PalimpediaWeb.ConvergenceController do
  use PalimpediaWeb, :controller

  alias Palimpedia.Interaction.Convergence

  @moduledoc """
  REST API for convergence detection analytics.
  Shows which topics have independent user agreement.
  """

  @doc "GET /api/convergence — List converged clusters."
  def index(conn, _params) do
    clusters = Convergence.converged_clusters()

    json(conn, %{
      data:
        Enum.map(clusters, fn c ->
          %{
            topic: c.topic,
            distinct_users: c.distinct_users,
            total_signals: c.total_signals,
            converged: c.converged,
            first_seen_at: DateTime.to_iso8601(c.first_seen_at),
            last_signal_at: DateTime.to_iso8601(c.last_signal_at)
          }
        end),
      meta: %{count: length(clusters)}
    })
  end

  @doc "GET /api/convergence/stats — Convergence metrics."
  def stats(conn, _params) do
    json(conn, %{data: Convergence.stats()})
  end
end
