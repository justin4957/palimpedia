defmodule PalimpediaWeb.SecurityController do
  use PalimpediaWeb, :controller

  alias Palimpedia.Security.{AntiPoisoning, HallucinationGuard}

  @moduledoc "REST API for security monitoring."

  def stats(conn, _params) do
    json(conn, %{data: AntiPoisoning.stats()})
  end

  def recent_blocks(conn, params) do
    limit = Map.get(params, "limit", "20") |> String.to_integer()
    blocks = AntiPoisoning.recent_blocks(limit)

    json(conn, %{
      data:
        Enum.map(blocks, fn b ->
          %{
            user_id: b.user_id,
            tier: b.tier,
            reason: b.reason,
            message: b.message,
            timestamp: DateTime.to_iso8601(b.timestamp)
          }
        end),
      meta: %{count: length(blocks)}
    })
  end

  def hallucination_stats(conn, _params) do
    json(conn, %{data: HallucinationGuard.stats()})
  end

  def hallucination_audit(conn, %{"node_id" => node_id_str}) do
    case Integer.parse(node_id_str) do
      {node_id, ""} ->
        case HallucinationGuard.audit_trail(node_id) do
          {:ok, entry} ->
            json(conn, %{
              data: %{
                context_node_ids: entry.context_node_ids,
                timestamp: DateTime.to_iso8601(entry.timestamp),
                success: entry.success
              }
            })

          {:error, :not_found} ->
            conn |> put_status(404) |> json(%{error: "No audit trail for this node"})
        end

      _ ->
        conn |> put_status(400) |> json(%{error: "Invalid node ID"})
    end
  end

  def hallucination_downstream(conn, %{"node_id" => node_id_str}) do
    case Integer.parse(node_id_str) do
      {node_id, ""} ->
        downstream = HallucinationGuard.downstream_of(node_id)

        json(conn, %{
          data:
            Enum.map(downstream, fn d ->
              %{
                generated_node_id: d.generated_node_id,
                timestamp: DateTime.to_iso8601(d.timestamp),
                success: d.success
              }
            end),
          meta: %{count: length(downstream)}
        })

      _ ->
        conn |> put_status(400) |> json(%{error: "Invalid node ID"})
    end
  end
end
