defmodule Palimpedia.Security.HallucinationGuard do
  @moduledoc """
  Hallucination propagation mitigation.

  Prevents wrong documents from becoming trusted nodes and stops
  downstream generation from inheriting and amplifying errors.

  ## Protections

  1. **Confidence ceiling**: ungrounded nodes (no anchor-traceable claims)
     cannot exceed 0.5 confidence
  2. **Generation audit**: tracks which nodes were used as context for
     each generated document, enabling error tracing
  3. **Circuit breaker**: halts generation in subgraph regions where
     the error rate exceeds a threshold
  """

  use GenServer

  require Logger

  @ungrounded_confidence_ceiling 0.5
  @circuit_breaker_threshold 0.3
  @circuit_breaker_window_size 20

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enforces the confidence ceiling for ungrounded documents.
  Returns the capped confidence score.
  """
  def enforce_confidence_ceiling(confidence, anchor_distance, provenance) do
    ungrounded = anchor_distance == nil or provenance == []

    if ungrounded and confidence > @ungrounded_confidence_ceiling do
      @ungrounded_confidence_ceiling
    else
      confidence
    end
  end

  @doc """
  Records a generation audit entry: which context nodes produced a generated document.
  """
  def record_generation(generated_node_id, context_node_ids, opts \\ []) do
    GenServer.call(__MODULE__, {:record_generation, generated_node_id, context_node_ids, opts})
  end

  @doc """
  Records a generation failure for circuit breaker tracking.
  """
  def record_failure(context_node_ids) do
    GenServer.call(__MODULE__, {:record_failure, context_node_ids})
  end

  @doc """
  Checks if generation should proceed for a given set of context nodes.
  Returns :ok or {:circuit_open, reason}.
  """
  def check_circuit(context_node_ids) do
    GenServer.call(__MODULE__, {:check_circuit, context_node_ids})
  end

  @doc "Returns the generation audit trail for a node."
  def audit_trail(node_id) do
    GenServer.call(__MODULE__, {:audit_trail, node_id})
  end

  @doc "Returns nodes that were generated using a specific context node."
  def downstream_of(context_node_id) do
    GenServer.call(__MODULE__, {:downstream_of, context_node_id})
  end

  @doc "Returns hallucination guard statistics."
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc "The confidence ceiling for ungrounded documents."
  def confidence_ceiling, do: @ungrounded_confidence_ceiling

  # --- GenServer ---

  @impl true
  def init(_opts) do
    {:ok,
     %{
       # generated_node_id -> %{context_node_ids, timestamp, success}
       audit_log: %{},
       # context_node_id -> [%{success: bool, timestamp}]
       circuit_state: %{},
       total_generations: 0,
       total_failures: 0,
       ceiling_enforcements: 0
     }}
  end

  @impl true
  def handle_call({:record_generation, generated_id, context_ids, _opts}, _from, state) do
    entry = %{
      context_node_ids: context_ids,
      timestamp: DateTime.utc_now(),
      success: true
    }

    state = %{
      state
      | audit_log: Map.put(state.audit_log, generated_id, entry),
        total_generations: state.total_generations + 1
    }

    # Record success in circuit state for each context node
    state = record_circuit_event(state, context_ids, true)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:record_failure, context_ids}, _from, state) do
    state = %{state | total_failures: state.total_failures + 1}
    state = record_circuit_event(state, context_ids, false)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:check_circuit, context_ids}, _from, state) do
    failed_nodes =
      Enum.filter(context_ids, fn node_id ->
        error_rate = calculate_error_rate(state, node_id)
        error_rate > @circuit_breaker_threshold
      end)

    result =
      if failed_nodes != [] do
        {:circuit_open,
         "Generation halted: high error rate in context nodes #{inspect(failed_nodes)}"}
      else
        :ok
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:audit_trail, node_id}, _from, state) do
    case Map.get(state.audit_log, node_id) do
      nil -> {:reply, {:error, :not_found}, state}
      entry -> {:reply, {:ok, entry}, state}
    end
  end

  @impl true
  def handle_call({:downstream_of, context_node_id}, _from, state) do
    downstream =
      state.audit_log
      |> Enum.filter(fn {_gen_id, entry} ->
        context_node_id in entry.context_node_ids
      end)
      |> Enum.map(fn {gen_id, entry} ->
        %{generated_node_id: gen_id, timestamp: entry.timestamp, success: entry.success}
      end)
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

    {:reply, downstream, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    total = state.total_generations + state.total_failures

    {:reply,
     %{
       total_generations: state.total_generations,
       total_failures: state.total_failures,
       error_rate: if(total > 0, do: Float.round(state.total_failures / total, 4), else: 0.0),
       audit_log_size: map_size(state.audit_log),
       circuit_breaker_threshold: @circuit_breaker_threshold,
       confidence_ceiling: @ungrounded_confidence_ceiling
     }, state}
  end

  # --- Private ---

  defp record_circuit_event(state, context_ids, success) do
    Enum.reduce(context_ids, state, fn node_id, st ->
      events = Map.get(st.circuit_state, node_id, [])
      event = %{success: success, timestamp: DateTime.utc_now()}
      trimmed = Enum.take([event | events], @circuit_breaker_window_size)
      %{st | circuit_state: Map.put(st.circuit_state, node_id, trimmed)}
    end)
  end

  defp calculate_error_rate(state, node_id) do
    events = Map.get(state.circuit_state, node_id, [])

    if events == [] do
      0.0
    else
      failures = Enum.count(events, &(not &1.success))
      failures / length(events)
    end
  end
end
