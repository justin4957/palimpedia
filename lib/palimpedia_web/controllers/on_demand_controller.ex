defmodule PalimpediaWeb.OnDemandController do
  use PalimpediaWeb, :controller

  alias Palimpedia.Generation.OnDemand
  alias PalimpediaWeb.GraphJSON

  @moduledoc """
  REST API for on-demand document generation.

  When a crawler or user requests a document that doesn't exist,
  evaluates structural pressure and enqueues for generation if
  the pressure exceeds the threshold.
  """

  @doc """
  GET /api/generate/evaluate?title=... — Evaluate a title for on-demand generation.

  Returns one of:
  - 200 with existing node data (document already exists)
  - 202 with pending status (enqueued for generation)
  - 200 with declined status (pressure too low)
  """
  def evaluate(conn, %{"title" => title}) when title != "" do
    case OnDemand.evaluate(title) do
      {:exists, node} ->
        json(conn, %{
          status: "exists",
          data: GraphJSON.node_to_json(node)
        })

      {:enqueued, request} ->
        conn
        |> put_status(202)
        |> json(%{
          status: "enqueued",
          data: %{
            title: request.title,
            pressure: Float.round(request.pressure, 3),
            queue_entry_id: request.queue_entry_id,
            poll_url: "/api/generate/status?title=#{URI.encode(request.title)}"
          },
          message: "Document enqueued for generation. Poll the status URL to check completion."
        })

      {:pending, request} ->
        conn
        |> put_status(202)
        |> json(%{
          status: "pending",
          data: %{
            title: request.title,
            pressure: Float.round(request.pressure, 3),
            queue_entry_id: request.queue_entry_id,
            poll_url: "/api/generate/status?title=#{URI.encode(request.title)}"
          },
          message: "Document already enqueued. Poll the status URL to check completion."
        })

      {:completed, request} ->
        json(conn, %{
          status: "completed",
          data: %{
            title: request.title,
            node_id: request.node_id,
            node_url: "/api/nodes/#{request.node_id}"
          }
        })

      {:declined, request} ->
        json(conn, %{
          status: "declined",
          data: %{
            title: request.title,
            pressure: Float.round(request.pressure, 3),
            threshold: 2.0
          },
          message:
            "Insufficient structural pressure. The graph does not yet have enough context to generate this document."
        })
    end
  end

  def evaluate(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Required query parameter: title"})
  end

  @doc "GET /api/generate/status?title=... — Poll generation status."
  def status(conn, %{"title" => title}) when title != "" do
    case OnDemand.status(title) do
      {:ok, :unknown} ->
        conn
        |> put_status(404)
        |> json(%{status: "unknown", message: "No generation request found for this title"})

      {:ok, %{status: :completed} = request} ->
        json(conn, %{
          status: "completed",
          data: %{
            title: request.title,
            node_id: request.node_id,
            node_url: "/api/nodes/#{request.node_id}"
          }
        })

      {:ok, request} ->
        json(conn, %{
          status: Atom.to_string(request.status),
          data: %{
            title: request.title,
            pressure: Float.round(request.pressure, 3),
            requested_at: DateTime.to_iso8601(request.requested_at)
          }
        })
    end
  end

  def status(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Required query parameter: title"})
  end

  @doc "GET /api/generate/pending — List all pending generation requests."
  def list_pending(conn, _params) do
    pending = OnDemand.list_pending()

    json(conn, %{
      data:
        Enum.map(pending, fn req ->
          %{
            title: req.title,
            status: req.status,
            pressure: Float.round(req.pressure, 3),
            requested_at: DateTime.to_iso8601(req.requested_at)
          }
        end),
      meta: %{count: length(pending)}
    })
  end
end
