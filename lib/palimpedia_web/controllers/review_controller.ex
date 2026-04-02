defmodule PalimpediaWeb.ReviewController do
  use PalimpediaWeb, :controller

  alias Palimpedia.Review.Queue, as: ReviewQueue

  @moduledoc """
  REST API for the human review queue.
  List pending reviews, approve/reject/flag documents.
  """

  @doc "GET /api/reviews — List pending review items."
  def index(conn, _params) do
    items = ReviewQueue.list_pending()

    json(conn, %{
      data: Enum.map(items, &review_to_json/1),
      meta: %{count: length(items)}
    })
  end

  @doc "GET /api/reviews/stats — Review queue metrics."
  def stats(conn, _params) do
    json(conn, %{data: ReviewQueue.stats()})
  end

  @doc "GET /api/reviews/:id — Get a single review item."
  def show(conn, %{"id" => review_id}) do
    case ReviewQueue.get(review_id) do
      {:ok, item} ->
        json(conn, %{data: review_to_json(item)})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Review item not found"})
    end
  end

  @doc "POST /api/reviews/:id/approve — Approve a review item."
  def approve(conn, %{"id" => review_id} = params) do
    note = Map.get(params, "note")

    case ReviewQueue.approve(review_id, note: note) do
      {:ok, item} ->
        apply_approval_effects(item)

        json(conn, %{
          data: review_to_json(item),
          meta: %{action: "approved", confidence_effect: "boosted"}
        })

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Review item not found"})
    end
  end

  @doc "POST /api/reviews/:id/reject — Reject a review item."
  def reject(conn, %{"id" => review_id} = params) do
    note = Map.get(params, "note")

    case ReviewQueue.reject(review_id, note: note) do
      {:ok, item} ->
        json(conn, %{
          data: review_to_json(item),
          meta: %{action: "rejected", effect: "queued_for_regeneration"}
        })

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Review item not found"})
    end
  end

  @doc "POST /api/reviews/:id/flag — Flag a review item for investigation."
  def flag(conn, %{"id" => review_id} = params) do
    note = Map.get(params, "note")

    case ReviewQueue.flag(review_id, note: note) do
      {:ok, item} ->
        json(conn, %{
          data: review_to_json(item),
          meta: %{action: "flagged"}
        })

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Review item not found"})
    end
  end

  # --- Private ---

  defp review_to_json(item) do
    %{
      id: item.id,
      node_id: item.node_id,
      node_title: item.node_title,
      reason: item.reason,
      status: item.status,
      submitted_at: DateTime.to_iso8601(item.submitted_at),
      reviewed_at: item.reviewed_at && DateTime.to_iso8601(item.reviewed_at),
      reviewer_note: item.reviewer_note
    }
  end

  defp apply_approval_effects(item) do
    graph_repo =
      Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)

    # Boost confidence by 0.1 on approval (capped at 1.0)
    case graph_repo.get_node(item.node_id) do
      {:ok, node} ->
        new_confidence = min(1.0, node.confidence + 0.1)
        graph_repo.update_confidence(node.id, new_confidence, node.anchor_distance)

      _ ->
        :ok
    end
  end
end
