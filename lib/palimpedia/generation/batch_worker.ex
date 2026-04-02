defmodule Palimpedia.Generation.BatchWorker do
  @moduledoc """
  Autonomous batch generation worker.

  Periodically dequeues entries from the GenerationQueue and runs the
  generation pipeline. Handles success/failure tracking, retry with
  exponential backoff, and metrics recording.

  ## Configuration

      config :palimpedia, Palimpedia.Generation.BatchWorker,
        enabled: true,
        interval_ms: :timer.seconds(30),
        batch_size: 5,
        max_retries: 3
  """

  use GenServer

  alias Palimpedia.GapDetection.GenerationQueue
  alias Palimpedia.Generation.{Pipeline, Metrics}

  require Logger

  @default_interval :timer.seconds(30)
  @default_batch_size 5
  @default_max_retries 3

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the worker status."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Triggers an immediate batch processing run."
  def run_now do
    GenServer.cast(__MODULE__, :run_now)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    config = Application.get_env(:palimpedia, __MODULE__, [])
    enabled = Keyword.get(config, :enabled, Keyword.get(opts, :enabled, true))

    interval =
      Keyword.get(config, :interval_ms, Keyword.get(opts, :interval_ms, @default_interval))

    batch_size =
      Keyword.get(config, :batch_size, Keyword.get(opts, :batch_size, @default_batch_size))

    max_retries =
      Keyword.get(config, :max_retries, Keyword.get(opts, :max_retries, @default_max_retries))

    pipeline_opts = Keyword.get(config, :pipeline_opts, Keyword.get(opts, :pipeline_opts, []))

    state = %{
      enabled: enabled,
      interval: interval,
      batch_size: batch_size,
      max_retries: max_retries,
      pipeline_opts: pipeline_opts,
      total_processed: 0,
      total_succeeded: 0,
      total_failed: 0,
      last_run_at: nil,
      timer_ref: nil
    }

    state =
      if enabled do
        ref = Process.send_after(self(), :process_batch, 10_000)
        %{state | timer_ref: ref}
      else
        state
      end

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     %{
       enabled: state.enabled,
       batch_size: state.batch_size,
       interval_ms: state.interval,
       total_processed: state.total_processed,
       total_succeeded: state.total_succeeded,
       total_failed: state.total_failed,
       last_run_at: state.last_run_at
     }, state}
  end

  @impl true
  def handle_cast(:run_now, state) do
    state = process_batch(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:process_batch, state) do
    state = process_batch(state)
    ref = Process.send_after(self(), :process_batch, state.interval)
    {:noreply, %{state | timer_ref: ref}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp process_batch(state) do
    results =
      1..state.batch_size
      |> Enum.reduce_while([], fn _i, acc ->
        case dequeue_entry() do
          {:ok, :empty} -> {:halt, acc}
          {:ok, :budget_exhausted} -> {:halt, acc}
          {:ok, entry} -> {:cont, [process_entry(entry, state) | acc]}
        end
      end)

    succeeded = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &(&1 == :error))

    if length(results) > 0 do
      Logger.info(
        "Batch generation: processed #{length(results)} entries " <>
          "(#{succeeded} succeeded, #{failed} failed)"
      )
    end

    %{
      state
      | total_processed: state.total_processed + length(results),
        total_succeeded: state.total_succeeded + succeeded,
        total_failed: state.total_failed + failed,
        last_run_at: DateTime.utc_now()
    }
  end

  defp process_entry(entry, state) do
    Logger.info("Generating document for: #{entry.suggested_title || entry.id}")

    case generate_for_entry(entry, state.pipeline_opts) do
      {:ok, result} ->
        complete_entry(entry.id)
        record_success(result)
        :ok

      {:error, reason} ->
        Logger.warning("Generation failed for #{entry.id}: #{inspect(reason)}")
        fail_entry(entry.id)
        record_failure(reason)
        maybe_retry(entry, reason, state.max_retries)
        :error
    end
  end

  defp generate_for_entry(entry, pipeline_opts) do
    context_node_ids = entry.context_node_ids

    case context_node_ids do
      [center_id | _] when is_integer(center_id) ->
        title = entry.suggested_title || "Bridge Document #{entry.id}"

        Pipeline.generate_from_graph(
          title,
          center_id,
          Keyword.merge(pipeline_opts, gap_type: entry.gap_type)
        )

      _ ->
        # No context node IDs — build a minimal context from the title
        title = entry.suggested_title || "Document #{entry.id}"

        context = %{
          target_title: title,
          subgraph_nodes: [],
          subgraph_edges: [],
          gap_type: entry.gap_type
        }

        Pipeline.generate(context, pipeline_opts)
    end
  end

  defp maybe_retry(entry, _reason, max_retries) do
    retry_count = entry.demand_count

    if retry_count < max_retries do
      # Re-enqueue with reduced priority (exponential backoff via lower priority)
      backoff_penalty = :math.pow(2, retry_count) * 1.0
      reduced_priority = max(0.0, entry.priority - backoff_penalty)

      re_entry = %{
        gap_type: entry.gap_type,
        priority: reduced_priority,
        suggested_title: entry.suggested_title,
        context: %{
          node_a_id: List.first(entry.context_node_ids),
          node_b_id: Enum.at(entry.context_node_ids, 1)
        }
      }

      case enqueue_retry(re_entry) do
        {:ok, _} ->
          Logger.info(
            "Re-enqueued #{entry.id} with priority #{reduced_priority} (retry #{retry_count + 1}/#{max_retries})"
          )

        _ ->
          :ok
      end
    end
  end

  # Wrappers that check if the GenServers are running (for testability)
  defp dequeue_entry do
    if Process.whereis(GenerationQueue), do: GenerationQueue.dequeue(), else: {:ok, :empty}
  end

  defp complete_entry(entry_id) do
    if Process.whereis(GenerationQueue), do: GenerationQueue.complete(entry_id)
  end

  defp fail_entry(entry_id) do
    if Process.whereis(GenerationQueue), do: GenerationQueue.fail(entry_id)
  end

  defp enqueue_retry(entry) do
    if Process.whereis(GenerationQueue), do: GenerationQueue.enqueue(entry), else: {:ok, nil}
  end

  defp record_success(result) do
    if Process.whereis(Metrics), do: Metrics.record_success(result)
  end

  defp record_failure(reason) do
    if Process.whereis(Metrics), do: Metrics.record_failure(reason)
  end
end
