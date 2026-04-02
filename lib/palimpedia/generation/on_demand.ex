defmodule Palimpedia.Generation.OnDemand do
  @moduledoc """
  On-demand generation evaluator.

  When a crawler or user requests a document that doesn't exist, evaluates
  whether it should be generated based on structural pressure from the
  existing graph. High-pressure requests are enqueued for generation;
  low-pressure requests are declined.

  Tracks pending generation requests so clients can poll for completion.
  """

  use GenServer

  alias Palimpedia.GapDetection.GenerationQueue

  require Logger

  @type pending_request :: %{
          title: String.t(),
          status: :evaluating | :enqueued | :generating | :completed | :declined,
          queue_entry_id: String.t() | nil,
          node_id: integer() | nil,
          pressure: float(),
          requested_at: DateTime.t(),
          completed_at: DateTime.t() | nil
        }

  @pressure_threshold 2.0

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Evaluates a title for on-demand generation.

  1. Searches the graph for existing nodes matching the title
  2. If found, returns the existing node
  3. If not found, evaluates relational pressure from similar nodes
  4. If pressure exceeds threshold, enqueues for generation
  5. Returns the pending request status for polling
  """
  def evaluate(title, opts \\ []) do
    GenServer.call(__MODULE__, {:evaluate, title, opts})
  end

  @doc "Returns the current status of a pending generation request."
  def status(title) do
    GenServer.call(__MODULE__, {:status, title})
  end

  @doc """
  Marks a pending request as completed with the generated node ID.
  Called by the generation pipeline after successful generation.
  """
  def mark_completed(title, node_id) do
    GenServer.call(__MODULE__, {:mark_completed, title, node_id})
  end

  @doc "Returns all pending requests."
  def list_pending do
    GenServer.call(__MODULE__, :list_pending)
  end

  # --- GenServer ---

  @impl true
  def init(_opts) do
    {:ok, %{requests: %{}}}
  end

  @impl true
  def handle_call({:evaluate, title, opts}, _from, state) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())
    normalized_title = String.trim(title)

    # Check if already pending
    case Map.get(state.requests, normalized_title) do
      %{status: status} = existing when status in [:enqueued, :generating] ->
        {:reply, {:pending, existing}, state}

      %{status: :completed} = existing ->
        {:reply, {:completed, existing}, state}

      _ ->
        # Search for existing node
        case graph_repo.search_nodes(normalized_title, limit: 1) do
          {:ok, [node | _]} when node.title == normalized_title ->
            {:reply, {:exists, node}, state}

          _ ->
            # Evaluate pressure
            {pressure, context_ids} = evaluate_pressure(normalized_title, graph_repo)

            {result, _request, state} =
              handle_pressure(normalized_title, pressure, context_ids, state)

            {:reply, result, state}
        end
    end
  end

  @impl true
  def handle_call({:status, title}, _from, state) do
    case Map.get(state.requests, String.trim(title)) do
      nil -> {:reply, {:ok, :unknown}, state}
      request -> {:reply, {:ok, request}, state}
    end
  end

  @impl true
  def handle_call({:mark_completed, title, node_id}, _from, state) do
    normalized = String.trim(title)

    case Map.get(state.requests, normalized) do
      nil ->
        {:reply, {:error, :not_found}, state}

      request ->
        updated = %{
          request
          | status: :completed,
            node_id: node_id,
            completed_at: DateTime.utc_now()
        }

        state = %{state | requests: Map.put(state.requests, normalized, updated)}
        {:reply, {:ok, updated}, state}
    end
  end

  @impl true
  def handle_call(:list_pending, _from, state) do
    pending =
      state.requests
      |> Enum.filter(fn {_title, req} -> req.status in [:enqueued, :generating, :evaluating] end)
      |> Enum.map(fn {_title, req} -> req end)
      |> Enum.sort_by(& &1.requested_at, {:desc, DateTime})

    {:reply, pending, state}
  end

  # --- Private ---

  defp handle_pressure(title, pressure, context_ids, state) do
    if pressure >= @pressure_threshold do
      request = %{
        title: title,
        status: :enqueued,
        queue_entry_id: nil,
        node_id: nil,
        pressure: pressure,
        requested_at: DateTime.utc_now(),
        completed_at: nil
      }

      # Enqueue for generation
      queue_entry_id = enqueue_for_generation(title, pressure, context_ids)
      request = %{request | queue_entry_id: queue_entry_id}

      state = %{state | requests: Map.put(state.requests, title, request)}

      Logger.info("On-demand: enqueued '#{title}' (pressure=#{Float.round(pressure, 2)})")
      {{:enqueued, request}, request, state}
    else
      request = %{
        title: title,
        status: :declined,
        queue_entry_id: nil,
        node_id: nil,
        pressure: pressure,
        requested_at: DateTime.utc_now(),
        completed_at: nil
      }

      state = %{state | requests: Map.put(state.requests, title, request)}

      Logger.info(
        "On-demand: declined '#{title}' (pressure=#{Float.round(pressure, 2)} < #{@pressure_threshold})"
      )

      {{:declined, request}, request, state}
    end
  end

  defp evaluate_pressure(title, graph_repo) do
    # Find related nodes by searching for words in the title
    words = title |> String.split(~r/\s+/) |> Enum.reject(&(String.length(&1) < 3))

    {related_nodes, context_ids} =
      Enum.reduce(words, {[], []}, fn word, {nodes_acc, ids_acc} ->
        case graph_repo.search_nodes(word, limit: 5) do
          {:ok, found} ->
            new_nodes = Enum.reject(found, fn n -> n.id in ids_acc end)
            new_ids = Enum.map(new_nodes, & &1.id)
            {nodes_acc ++ new_nodes, ids_acc ++ new_ids}

          _ ->
            {nodes_acc, ids_acc}
        end
      end)

    # Pressure = number of related nodes * average confidence
    if related_nodes == [] do
      {0.0, []}
    else
      avg_confidence =
        related_nodes
        |> Enum.map(& &1.confidence)
        |> Enum.sum()
        |> Kernel./(length(related_nodes))

      pressure = length(related_nodes) * avg_confidence
      {pressure, Enum.take(context_ids, 5)}
    end
  end

  defp enqueue_for_generation(title, pressure, context_ids) do
    gap = %{
      gap_type: :on_demand,
      priority: pressure + 5.0,
      suggested_title: title,
      context: %{
        node_a_id: List.first(context_ids),
        node_b_id: Enum.at(context_ids, 1)
      }
    }

    if Process.whereis(GenerationQueue) do
      case GenerationQueue.enqueue(gap) do
        {:ok, entry} -> entry.id
        _ -> nil
      end
    else
      nil
    end
  end

  defp graph_repository do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
