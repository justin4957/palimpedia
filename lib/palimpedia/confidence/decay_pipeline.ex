defmodule Palimpedia.Confidence.DecayPipeline do
  @moduledoc """
  Scheduled temporal confidence decay and re-evaluation pipeline.

  Periodically:
  1. Applies temporal decay to all generated nodes
  2. Flags stale documents (old + low confidence) for review/regeneration
  3. Handles anchor corpus update triggers — re-evaluates downstream nodes

  ## Configuration

      config :palimpedia, Palimpedia.Confidence.DecayPipeline,
        enabled: true,
        interval_ms: :timer.hours(1),
        staleness_threshold_days: 90,
        staleness_confidence_floor: 0.3
  """

  use GenServer

  alias Palimpedia.Confidence.{Scorer, Updater}
  alias Palimpedia.Review.Queue, as: ReviewQueue

  require Logger

  @default_interval :timer.hours(1)
  @default_staleness_days 90
  @default_confidence_floor 0.3

  @type sweep_result :: %{
          decayed: non_neg_integer(),
          flagged_stale: non_neg_integer(),
          cascade_updated: non_neg_integer(),
          errors: non_neg_integer()
        }

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Runs a full decay sweep immediately."
  def run_sweep do
    GenServer.call(__MODULE__, :run_sweep, 60_000)
  end

  @doc """
  Triggers re-evaluation of all nodes within N hops of an updated anchor.
  Call this after an anchor corpus source is updated/re-ingested.
  """
  def trigger_anchor_update(anchor_node_id, opts \\ []) do
    GenServer.call(__MODULE__, {:anchor_update, anchor_node_id, opts})
  end

  @doc "Returns the last sweep result and status."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # --- GenServer ---

  @impl true
  def init(opts) do
    config = Application.get_env(:palimpedia, __MODULE__, [])
    enabled = Keyword.get(config, :enabled, Keyword.get(opts, :enabled, true))

    interval =
      Keyword.get(config, :interval_ms, Keyword.get(opts, :interval_ms, @default_interval))

    state = %{
      enabled: enabled,
      interval: interval,
      staleness_days: Keyword.get(config, :staleness_threshold_days, @default_staleness_days),
      confidence_floor:
        Keyword.get(config, :staleness_confidence_floor, @default_confidence_floor),
      last_sweep: nil,
      last_sweep_at: nil,
      total_sweeps: 0,
      timer_ref: nil
    }

    state =
      if enabled do
        ref = Process.send_after(self(), :sweep, 30_000)
        %{state | timer_ref: ref}
      else
        state
      end

    {:ok, state}
  end

  @impl true
  def handle_call(:run_sweep, _from, state) do
    {result, state} = do_sweep(state)
    {:reply, {:ok, result}, state}
  end

  @impl true
  def handle_call({:anchor_update, anchor_node_id, opts}, _from, state) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())
    hops = Keyword.get(opts, :hops, 3)

    result = cascade_from_anchor(anchor_node_id, graph_repo, hops)
    {:reply, {:ok, result}, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     %{
       enabled: state.enabled,
       interval_ms: state.interval,
       last_sweep: state.last_sweep,
       last_sweep_at: state.last_sweep_at,
       total_sweeps: state.total_sweeps
     }, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    {_result, state} = do_sweep(state)
    ref = Process.send_after(self(), :sweep, state.interval)
    {:noreply, %{state | timer_ref: ref}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp do_sweep(state) do
    graph_repo = graph_repository()

    Logger.info("Decay sweep starting...")

    decay_result = apply_decay_to_generated(graph_repo)
    stale_result = flag_stale_documents(graph_repo, state.staleness_days, state.confidence_floor)

    result = %{
      decayed: decay_result.decayed,
      flagged_stale: stale_result.flagged,
      cascade_updated: 0,
      errors: decay_result.errors + stale_result.errors
    }

    Logger.info(
      "Decay sweep complete: #{result.decayed} decayed, #{result.flagged_stale} flagged stale, #{result.errors} errors"
    )

    state = %{
      state
      | last_sweep: result,
        last_sweep_at: DateTime.utc_now(),
        total_sweeps: state.total_sweeps + 1
    }

    {result, state}
  end

  defp apply_decay_to_generated(graph_repo) do
    case graph_repo.find_generated_nodes(limit: 500) do
      {:ok, nodes} ->
        Enum.reduce(nodes, %{decayed: 0, errors: 0}, fn node, acc ->
          case apply_decay_to_node(node, graph_repo) do
            {:ok, _} -> %{acc | decayed: acc.decayed + 1}
            {:error, _} -> %{acc | errors: acc.errors + 1}
          end
        end)

      {:error, _} ->
        %{decayed: 0, errors: 1}
    end
  end

  defp apply_decay_to_node(node, graph_repo) do
    case node.generated_at do
      nil ->
        {:ok, node}

      generated_at ->
        decayed_confidence = Scorer.apply_temporal_decay(node.confidence, generated_at)

        if abs(decayed_confidence - node.confidence) > 0.001 do
          graph_repo.update_confidence(node.id, decayed_confidence, node.anchor_distance)
        else
          {:ok, node}
        end
    end
  end

  defp flag_stale_documents(graph_repo, staleness_days, confidence_floor) do
    case graph_repo.find_stale_nodes(staleness_days, limit: 100) do
      {:ok, nodes} ->
        stale_nodes = Enum.filter(nodes, &(&1.confidence < confidence_floor))

        flagged =
          Enum.count(stale_nodes, fn node ->
            submit_for_review(node)
          end)

        %{flagged: flagged, errors: 0}

      {:error, _} ->
        %{flagged: 0, errors: 1}
    end
  end

  defp submit_for_review(node) do
    if Process.whereis(ReviewQueue) do
      case ReviewQueue.submit(node.id, node.title, :staleness) do
        {:ok, _} -> true
        _ -> false
      end
    else
      false
    end
  end

  defp cascade_from_anchor(anchor_node_id, graph_repo, hops) do
    Logger.info("Cascading re-evaluation from anchor #{anchor_node_id} (#{hops} hops)")

    case Updater.recalculate_subgraph(anchor_node_id, graph_repo, hops: hops) do
      {:ok, result} ->
        Logger.info("Cascade complete: #{result.updated} nodes updated")
        result

      {:error, reason} ->
        Logger.error("Cascade failed: #{inspect(reason)}")
        %{updated: 0, flagged_for_regrounding: 0, errors: [reason]}
    end
  end

  defp graph_repository do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
