defmodule PalimpediaWeb.RevisionController do
  use PalimpediaWeb, :controller

  alias Palimpedia.Generation.RevisionHistory

  @moduledoc "REST API for document revision history."

  def recent(conn, params) do
    limit = Map.get(params, "limit", "20") |> String.to_integer()
    revisions = RevisionHistory.recent(limit)

    json(conn, %{
      data: Enum.map(revisions, &revision_to_json/1),
      meta: %{count: length(revisions)}
    })
  end

  def stats(conn, _params) do
    json(conn, %{data: RevisionHistory.stats()})
  end

  def history_for(conn, %{"node_id" => node_id_str}) do
    case Integer.parse(node_id_str) do
      {node_id, ""} ->
        history = RevisionHistory.history_for(node_id)

        json(conn, %{
          data: Enum.map(history, &revision_to_json/1),
          meta: %{node_id: node_id, count: length(history)}
        })

      _ ->
        conn |> put_status(400) |> json(%{error: "Invalid node ID"})
    end
  end

  defp revision_to_json(rev) do
    %{
      id: rev.id,
      node_id: rev.node_id,
      node_title: rev.node_title,
      trigger: rev.trigger,
      old_confidence: rev.old_confidence,
      new_confidence: rev.new_confidence,
      diff_summary: rev.diff_summary,
      revised_at: DateTime.to_iso8601(rev.revised_at)
    }
  end
end
