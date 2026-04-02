defmodule PalimpediaWeb.SecurityController do
  use PalimpediaWeb, :controller

  alias Palimpedia.Security.AntiPoisoning

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
end
