defmodule PalimpediaWeb.ExportController do
  use PalimpediaWeb, :controller

  alias Palimpedia.Export.Snapshot

  @moduledoc "REST API for graph export in RDF and JSON-LD formats."

  @doc "POST /api/export/snapshot — Create a new snapshot."
  def create_snapshot(conn, %{"format" => format_str}) do
    format = parse_format(format_str)

    if format do
      case Snapshot.create(format) do
        {:ok, metadata} ->
          conn |> put_status(201) |> json(%{data: metadata})

        {:error, reason} ->
          conn |> put_status(500) |> json(%{error: inspect(reason)})
      end
    else
      conn |> put_status(400) |> json(%{error: "Invalid format. Use 'rdf' or 'json_ld'"})
    end
  end

  def create_snapshot(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Required: format (rdf or json_ld)"})
  end

  @doc "GET /api/export/snapshots — List all snapshots."
  def list_snapshots(conn, _params) do
    snapshots = Snapshot.list_snapshots()

    json(conn, %{
      data: snapshots,
      meta: %{count: length(snapshots)}
    })
  end

  @doc "GET /api/export/snapshots/:id — Download a snapshot."
  def get_snapshot(conn, %{"id" => snapshot_id}) do
    case Snapshot.get_snapshot(snapshot_id) do
      {:ok, metadata, content} ->
        content_type =
          case metadata.format do
            :rdf -> "application/n-triples"
            :json_ld -> "application/ld+json"
          end

        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"#{snapshot_id}.#{ext(metadata.format)}\""
        )
        |> send_resp(200, content)

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "Snapshot not found"})
    end
  end

  @doc "GET /api/export/diff — Diff between two snapshots."
  def diff(conn, %{"a" => id_a, "b" => id_b}) do
    case Snapshot.diff(id_a, id_b) do
      {:ok, diff_result} -> json(conn, %{data: diff_result})
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "Snapshot not found"})
    end
  end

  def diff(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Required: a and b (snapshot IDs)"})
  end

  defp parse_format("rdf"), do: :rdf
  defp parse_format("json_ld"), do: :json_ld
  defp parse_format("jsonld"), do: :json_ld
  defp parse_format(_), do: nil

  defp ext(:rdf), do: "nt"
  defp ext(:json_ld), do: "jsonld"
end
