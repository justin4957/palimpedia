defmodule PalimpediaWeb.Plugs.RateLimiter do
  @moduledoc """
  Simple IP-based rate limiter using ETS.

  Limits requests per IP within a configurable time window.
  Returns 429 Too Many Requests when the limit is exceeded.

  ## Configuration

      config :palimpedia, PalimpediaWeb.Plugs.RateLimiter,
        max_requests: 60,
        window_ms: 60_000
  """

  import Plug.Conn

  @behaviour Plug

  @default_max_requests 60
  @default_window_ms 60_000

  @impl true
  def init(opts) do
    config = Application.get_env(:palimpedia, __MODULE__, [])

    %{
      max_requests:
        Keyword.get(
          opts,
          :max_requests,
          Keyword.get(config, :max_requests, @default_max_requests)
        ),
      window_ms:
        Keyword.get(opts, :window_ms, Keyword.get(config, :window_ms, @default_window_ms)),
      table: ensure_table()
    }
  end

  @impl true
  def call(conn, opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    now = System.monotonic_time(:millisecond)
    window_start = now - opts.window_ms

    # Clean old entries and count current window
    clean_and_count(opts.table, ip, window_start)
    count = count_requests(opts.table, ip, window_start)

    if count >= opts.max_requests do
      conn
      |> put_resp_header("retry-after", to_string(div(opts.window_ms, 1000)))
      |> put_resp_header("x-ratelimit-limit", to_string(opts.max_requests))
      |> put_resp_header("x-ratelimit-remaining", "0")
      |> send_resp(
        429,
        Jason.encode!(%{
          error: "Rate limit exceeded",
          retry_after_seconds: div(opts.window_ms, 1000)
        })
      )
      |> halt()
    else
      :ets.insert(opts.table, {{ip, now}, true})

      conn
      |> put_resp_header("x-ratelimit-limit", to_string(opts.max_requests))
      |> put_resp_header("x-ratelimit-remaining", to_string(opts.max_requests - count - 1))
    end
  end

  defp ensure_table do
    case :ets.whereis(:rate_limiter) do
      :undefined -> :ets.new(:rate_limiter, [:set, :public, :named_table])
      ref -> ref
    end
  end

  defp clean_and_count(table, ip, window_start) do
    :ets.select_delete(table, [{{{ip, :"$1"}, :_}, [{:<, :"$1", window_start}], [true]}])
  end

  defp count_requests(table, ip, window_start) do
    :ets.select_count(table, [{{{ip, :"$1"}, :_}, [{:>=, :"$1", window_start}], [true]}])
  end
end
