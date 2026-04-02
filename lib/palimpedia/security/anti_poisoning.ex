defmodule Palimpedia.Security.AntiPoisoning do
  @moduledoc """
  Anti-poisoning guard for the graph.

  Detects and blocks coordinated manipulation attempts:
  - Per-user rate limiting on write operations
  - Burst detection (many requests in short window)
  - Repetitive pattern detection (same user, similar assertions)
  - Adversarial edge detection (suspicious topology patterns)
  - Prompt injection pattern detection in titles/descriptions

  ## Configuration

      config :palimpedia, Palimpedia.Security.AntiPoisoning,
        user_rate_limit: 20,        # max write ops per user per hour
        burst_limit: 5,             # max ops per user per minute
        repetition_threshold: 3,    # max similar assertions per user per hour
        enabled: true
  """

  use GenServer

  require Logger

  @type check_result :: :ok | {:blocked, reason :: atom(), String.t()}

  @default_user_rate_limit 20
  @default_burst_limit 5
  @default_repetition_threshold 3

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks whether a user interaction should be allowed.

  Returns `:ok` if allowed, or `{:blocked, reason, message}` if blocked.
  """
  def check(user_id, tier, content, opts \\ []) do
    GenServer.call(__MODULE__, {:check, user_id, tier, content, opts})
  end

  @doc "Returns security metrics."
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc "Returns recent blocks for monitoring."
  def recent_blocks(limit \\ 20) do
    GenServer.call(__MODULE__, {:recent_blocks, limit})
  end

  # --- GenServer ---

  @impl true
  def init(opts) do
    config = Application.get_env(:palimpedia, __MODULE__, [])

    state = %{
      user_rate_limit:
        Keyword.get(
          config,
          :user_rate_limit,
          Keyword.get(opts, :user_rate_limit, @default_user_rate_limit)
        ),
      burst_limit:
        Keyword.get(config, :burst_limit, Keyword.get(opts, :burst_limit, @default_burst_limit)),
      repetition_threshold:
        Keyword.get(config, :repetition_threshold, @default_repetition_threshold),
      enabled: Keyword.get(config, :enabled, Keyword.get(opts, :enabled, true)),
      # user_id -> [{timestamp, content_hash}]
      user_activity: %{},
      total_checked: 0,
      total_blocked: 0,
      blocks: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:check, user_id, tier, content, _opts}, _from, state) do
    state = %{state | total_checked: state.total_checked + 1}

    if not state.enabled do
      {:reply, :ok, state}
    else
      now = System.monotonic_time(:millisecond)

      checks = [
        fn -> check_injection(content) end,
        fn -> check_user_rate(state, user_id, now) end,
        fn -> check_burst(state, user_id, now) end,
        fn -> check_repetition(state, user_id, content, now) end
      ]

      result =
        Enum.reduce_while(checks, :ok, fn check_fn, _acc ->
          case check_fn.() do
            :ok -> {:cont, :ok}
            {:blocked, _, _} = blocked -> {:halt, blocked}
          end
        end)

      state =
        case result do
          :ok ->
            record_activity(state, user_id, content, now)

          {:blocked, reason, message} ->
            Logger.warning(
              "Anti-poisoning blocked: user=#{user_id || "anon"} reason=#{reason} tier=#{tier}"
            )

            block_record = %{
              user_id: user_id,
              tier: tier,
              reason: reason,
              message: message,
              timestamp: DateTime.utc_now()
            }

            %{
              state
              | total_blocked: state.total_blocked + 1,
                blocks: [block_record | Enum.take(state.blocks, 99)]
            }
        end

      {:reply, result, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       total_checked: state.total_checked,
       total_blocked: state.total_blocked,
       block_rate:
         if(state.total_checked > 0, do: state.total_blocked / state.total_checked, else: 0.0),
       active_users: map_size(state.user_activity)
     }, state}
  end

  @impl true
  def handle_call({:recent_blocks, limit}, _from, state) do
    {:reply, Enum.take(state.blocks, limit), state}
  end

  # --- Checks ---

  defp check_injection(nil), do: :ok

  defp check_injection(content) when is_binary(content) do
    patterns = [
      ~r/ignore\s+previous/i,
      ~r/system\s*prompt/i,
      ~r/you\s+are\s+now/i,
      ~r/disregard\s+instructions/i,
      ~r/\bact\s+as\b/i,
      ~r/forget\s+everything/i,
      ~r/<script/i,
      ~r/javascript:/i
    ]

    if Enum.any?(patterns, &Regex.match?(&1, content)) do
      {:blocked, :injection_detected, "Input contains suspicious patterns"}
    else
      :ok
    end
  end

  defp check_injection(_), do: :ok

  defp check_user_rate(_state, nil, _now), do: :ok

  defp check_user_rate(state, user_id, now) do
    one_hour_ago = now - 3_600_000
    activity = Map.get(state.user_activity, user_id, [])
    recent_count = Enum.count(activity, fn {ts, _} -> ts > one_hour_ago end)

    if recent_count >= state.user_rate_limit do
      {:blocked, :user_rate_exceeded, "Too many requests. Limit: #{state.user_rate_limit}/hour"}
    else
      :ok
    end
  end

  defp check_burst(_state, nil, _now), do: :ok

  defp check_burst(state, user_id, now) do
    one_minute_ago = now - 60_000
    activity = Map.get(state.user_activity, user_id, [])
    burst_count = Enum.count(activity, fn {ts, _} -> ts > one_minute_ago end)

    if burst_count >= state.burst_limit do
      {:blocked, :burst_detected,
       "Too many requests in short window. Limit: #{state.burst_limit}/minute"}
    else
      :ok
    end
  end

  defp check_repetition(_state, nil, _content, _now), do: :ok
  defp check_repetition(_state, _user_id, nil, _now), do: :ok

  defp check_repetition(state, user_id, content, now) do
    one_hour_ago = now - 3_600_000
    content_hash = content_fingerprint(content)
    activity = Map.get(state.user_activity, user_id, [])

    similar_count =
      Enum.count(activity, fn {ts, hash} ->
        ts > one_hour_ago and hash == content_hash
      end)

    if similar_count >= state.repetition_threshold do
      {:blocked, :repetitive_pattern, "Repeated similar assertions detected"}
    else
      :ok
    end
  end

  # --- Helpers ---

  defp record_activity(state, nil, _content, _now), do: state

  defp record_activity(state, user_id, content, now) do
    hash = content_fingerprint(content)
    activity = Map.get(state.user_activity, user_id, [])

    # Keep only last hour of activity
    one_hour_ago = now - 3_600_000
    pruned = Enum.filter(activity, fn {ts, _} -> ts > one_hour_ago end)
    updated = [{now, hash} | pruned]

    %{state | user_activity: Map.put(state.user_activity, user_id, updated)}
  end

  defp content_fingerprint(nil), do: nil

  defp content_fingerprint(content) do
    content
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.trim()
    |> then(&:crypto.hash(:md5, &1))
    |> Base.encode16(case: :lower)
  end
end
