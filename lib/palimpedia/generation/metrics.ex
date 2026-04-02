defmodule Palimpedia.Generation.Metrics do
  @moduledoc """
  Tracks generation pipeline throughput metrics.

  Maintains running totals for success/failure counts, token usage,
  cost, and confidence distribution. Metrics reset on a configurable
  window (default: hourly).
  """

  use GenServer

  @type snapshot :: %{
          total_generated: non_neg_integer(),
          total_failed: non_neg_integer(),
          success_rate: float(),
          total_input_tokens: non_neg_integer(),
          total_output_tokens: non_neg_integer(),
          total_cost: float(),
          avg_confidence: float() | nil,
          window_start: DateTime.t()
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Records a successful generation."
  def record_success(generation_result) do
    GenServer.cast(__MODULE__, {:success, generation_result})
  end

  @doc "Records a failed generation."
  def record_failure(reason) do
    GenServer.cast(__MODULE__, {:failure, reason})
  end

  @doc "Returns a snapshot of current metrics."
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @doc "Resets all metrics."
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # --- GenServer ---

  @impl true
  def init(_opts) do
    {:ok, initial_state()}
  end

  @impl true
  def handle_cast({:success, result}, state) do
    token_usage = result[:token_usage] || %{input: 0, output: 0}
    cost = result[:estimated_cost] || 0.0
    confidence = get_in(result, [:node, Access.key(:confidence)]) || 0.0

    state = %{
      state
      | total_generated: state.total_generated + 1,
        total_input_tokens: state.total_input_tokens + (token_usage[:input] || 0),
        total_output_tokens: state.total_output_tokens + (token_usage[:output] || 0),
        total_cost: state.total_cost + cost,
        confidence_sum: state.confidence_sum + confidence
    }

    {:noreply, state}
  end

  @impl true
  def handle_cast({:failure, _reason}, state) do
    {:noreply, %{state | total_failed: state.total_failed + 1}}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    total = state.total_generated + state.total_failed

    success_rate =
      if total > 0, do: state.total_generated / total, else: 0.0

    avg_confidence =
      if state.total_generated > 0,
        do: state.confidence_sum / state.total_generated,
        else: nil

    snapshot = %{
      total_generated: state.total_generated,
      total_failed: state.total_failed,
      success_rate: success_rate,
      total_input_tokens: state.total_input_tokens,
      total_output_tokens: state.total_output_tokens,
      total_cost: state.total_cost,
      avg_confidence: avg_confidence,
      window_start: state.window_start
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, initial_state()}
  end

  defp initial_state do
    %{
      total_generated: 0,
      total_failed: 0,
      total_input_tokens: 0,
      total_output_tokens: 0,
      total_cost: 0.0,
      confidence_sum: 0.0,
      window_start: DateTime.utc_now()
    }
  end
end
