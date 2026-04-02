defmodule Palimpedia.GapDetection.Scheduler do
  @moduledoc """
  Scheduled recurring gap analysis.

  Runs the gap detection analyzer on a configurable interval and
  stores the latest results. Implemented as a GenServer with
  `:timer.send_interval` for simplicity — can be migrated to Oban
  when a Postgres dependency is added.

  ## Configuration

      config :palimpedia, Palimpedia.GapDetection.Scheduler,
        enabled: true,
        interval_ms: :timer.minutes(30),
        analyzer_opts: [min_edges: 2, structural_hole_hops: 3, limit: 50]
  """

  use GenServer

  alias Palimpedia.GapDetection.Analyzer

  require Logger

  @default_interval :timer.minutes(30)

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the latest analysis result, or nil if no analysis has run yet."
  def latest_result do
    GenServer.call(__MODULE__, :latest_result)
  end

  @doc "Triggers an immediate analysis run (async)."
  def run_now do
    GenServer.cast(__MODULE__, :run_now)
  end

  @doc "Returns the scheduler status: enabled, interval, last run time."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    config = Application.get_env(:palimpedia, __MODULE__, [])
    enabled = Keyword.get(config, :enabled, Keyword.get(opts, :enabled, true))

    interval =
      Keyword.get(config, :interval_ms, Keyword.get(opts, :interval_ms, @default_interval))

    analyzer_opts = Keyword.get(config, :analyzer_opts, Keyword.get(opts, :analyzer_opts, []))

    state = %{
      enabled: enabled,
      interval: interval,
      analyzer_opts: analyzer_opts,
      latest_result: nil,
      last_run_at: nil,
      timer_ref: nil
    }

    state =
      if enabled do
        # Run first analysis after a short delay to let the app start
        ref = Process.send_after(self(), :run_analysis, 5_000)
        %{state | timer_ref: ref}
      else
        state
      end

    {:ok, state}
  end

  @impl true
  def handle_call(:latest_result, _from, state) do
    {:reply, state.latest_result, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      enabled: state.enabled,
      interval_ms: state.interval,
      last_run_at: state.last_run_at,
      gap_count:
        if state.latest_result do
          state.latest_result.stats.total_gaps
        else
          nil
        end
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast(:run_now, state) do
    state = do_analyze(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:run_analysis, state) do
    state = do_analyze(state)

    # Schedule next run
    ref = Process.send_after(self(), :run_analysis, state.interval)
    {:noreply, %{state | timer_ref: ref}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private ---

  defp do_analyze(state) do
    Logger.info("Scheduled gap analysis starting...")

    {:ok, result} = Analyzer.analyze(state.analyzer_opts)

    Logger.info(
      "Scheduled gap analysis complete: #{result.stats.total_gaps} gaps " <>
        "(#{result.stats.structural_holes} holes, #{result.stats.orphans} orphans, " <>
        "#{result.stats.low_connectivity} low-conn, #{result.stats.asymmetric_coverage} coverage)"
    )

    %{state | latest_result: result, last_run_at: DateTime.utc_now()}
  end
end
