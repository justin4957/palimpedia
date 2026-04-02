defmodule PalimpediaWeb.Plugs.RateLimiterTest do
  use PalimpediaWeb.ConnCase, async: false

  alias PalimpediaWeb.Plugs.RateLimiter

  describe "rate limiting" do
    test "allows requests under the limit", %{conn: conn} do
      opts = RateLimiter.init(max_requests: 5, window_ms: 60_000)

      conn = RateLimiter.call(conn, opts)
      refute conn.halted

      assert get_resp_header(conn, "x-ratelimit-limit") == ["5"]
      remaining = get_resp_header(conn, "x-ratelimit-remaining") |> hd() |> String.to_integer()
      assert remaining >= 0
    end

    test "blocks requests over the limit", %{conn: conn} do
      # Use a very small limit so existing entries from other tests don't matter.
      # The shared ETS table accumulates entries from all API tests using 127.0.0.1.
      # We use a tiny window so prior entries expire.
      opts = RateLimiter.init(max_requests: 1, window_ms: 10)
      Process.sleep(15)

      # First request allowed
      first = RateLimiter.call(conn, opts)
      refute first.halted

      # Second should be blocked
      blocked_conn = RateLimiter.call(conn, opts)
      assert blocked_conn.halted
      assert blocked_conn.status == 429
      assert get_resp_header(blocked_conn, "retry-after") != []
      assert get_resp_header(blocked_conn, "x-ratelimit-remaining") == ["0"]
    end

    test "includes rate limit headers in response", %{conn: conn} do
      opts = RateLimiter.init(max_requests: 100, window_ms: 60_000)
      conn = RateLimiter.call(conn, opts)

      assert get_resp_header(conn, "x-ratelimit-limit") == ["100"]
    end
  end
end
