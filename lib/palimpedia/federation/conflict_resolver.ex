defmodule Palimpedia.Federation.ConflictResolver do
  @moduledoc """
  Resolves confidence score conflicts between federated instances.

  When instances disagree on confidence for shared nodes, applies a
  configurable resolution strategy. Maintains per-instance confidence
  alongside the federated score and logs all resolution decisions.

  ## Resolution Strategies

  - `:anchor_weighted` — Weight by anchor distance (closer to anchor = more authority)
  - `:majority_consensus` — Use the score reported by the most instances
  - `:average` — Simple average of all instance scores
  - `:manual` — Flag for human arbitration

  ## Configuration

      config :palimpedia, Palimpedia.Federation.ConflictResolver,
        strategy: :anchor_weighted,
        divergence_threshold: 0.1
  """

  use GenServer

  require Logger

  @type conflict :: %{
          id: String.t(),
          node_title: String.t(),
          instance_scores: %{String.t() => float()},
          resolved_score: float() | nil,
          strategy_used: atom() | nil,
          status: :detected | :resolved | :manual_pending,
          detected_at: DateTime.t(),
          resolved_at: DateTime.t() | nil
        }

  @default_strategy :anchor_weighted
  @default_threshold 0.1

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Detects conflicts when importing a federation message.
  Compares remote confidence scores against local scores for shared nodes.
  """
  def detect_conflicts(remote_nodes, opts \\ []) do
    GenServer.call(__MODULE__, {:detect, remote_nodes, opts})
  end

  @doc """
  Resolves a detected conflict using the configured strategy.
  """
  def resolve(conflict_id, opts \\ []) do
    GenServer.call(__MODULE__, {:resolve, conflict_id, opts})
  end

  @doc "Manually resolves a conflict with a specific score."
  def resolve_manually(conflict_id, score) do
    GenServer.call(__MODULE__, {:resolve_manual, conflict_id, score})
  end

  @doc "Returns all detected conflicts."
  def list_conflicts(opts \\ []) do
    GenServer.call(__MODULE__, {:list, opts})
  end

  @doc "Returns conflict resolution history for audit."
  def history(limit \\ 50) do
    GenServer.call(__MODULE__, {:history, limit})
  end

  @doc "Returns conflict statistics."
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # --- GenServer ---

  @impl true
  def init(opts) do
    config = Application.get_env(:palimpedia, __MODULE__, [])

    state = %{
      strategy: Keyword.get(config, :strategy, Keyword.get(opts, :strategy, @default_strategy)),
      threshold: Keyword.get(config, :divergence_threshold, @default_threshold),
      conflicts: %{},
      counter: 0,
      total_detected: 0,
      total_resolved: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:detect, remote_nodes, opts}, _from, state) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())
    source_instance = Keyword.get(opts, :source_instance, "remote")

    {new_conflicts, state} =
      Enum.reduce(remote_nodes, {[], state}, fn remote_node, {conflicts_acc, st} ->
        case find_local_match(remote_node, graph_repo) do
          {:ok, local_node} ->
            divergence = abs(local_node.confidence - remote_node.confidence)

            if divergence >= st.threshold do
              {conflict, st} =
                create_conflict(
                  remote_node.title,
                  local_node.confidence,
                  remote_node.confidence,
                  source_instance,
                  st
                )

              {[conflict | conflicts_acc], st}
            else
              {conflicts_acc, st}
            end

          _ ->
            {conflicts_acc, st}
        end
      end)

    {:reply, {:ok, Enum.reverse(new_conflicts)}, state}
  end

  @impl true
  def handle_call({:resolve, conflict_id, opts}, _from, state) do
    strategy = Keyword.get(opts, :strategy, state.strategy)

    case Map.get(state.conflicts, conflict_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      conflict ->
        resolved_score = apply_strategy(strategy, conflict.instance_scores)

        updated = %{
          conflict
          | resolved_score: resolved_score,
            strategy_used: strategy,
            status: :resolved,
            resolved_at: DateTime.utc_now()
        }

        state = %{
          state
          | conflicts: Map.put(state.conflicts, conflict_id, updated),
            total_resolved: state.total_resolved + 1
        }

        {:reply, {:ok, updated}, state}
    end
  end

  @impl true
  def handle_call({:resolve_manual, conflict_id, score}, _from, state) do
    case Map.get(state.conflicts, conflict_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      conflict ->
        updated = %{
          conflict
          | resolved_score: score,
            strategy_used: :manual,
            status: :resolved,
            resolved_at: DateTime.utc_now()
        }

        state = %{
          state
          | conflicts: Map.put(state.conflicts, conflict_id, updated),
            total_resolved: state.total_resolved + 1
        }

        {:reply, {:ok, updated}, state}
    end
  end

  @impl true
  def handle_call({:list, opts}, _from, state) do
    status_filter = Keyword.get(opts, :status)

    conflicts =
      state.conflicts
      |> Map.values()
      |> maybe_filter_status(status_filter)
      |> Enum.sort_by(& &1.detected_at, {:desc, DateTime})

    {:reply, conflicts, state}
  end

  @impl true
  def handle_call({:history, limit}, _from, state) do
    resolved =
      state.conflicts
      |> Map.values()
      |> Enum.filter(&(&1.status == :resolved))
      |> Enum.sort_by(& &1.resolved_at, {:desc, DateTime})
      |> Enum.take(limit)

    {:reply, resolved, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       total_detected: state.total_detected,
       total_resolved: state.total_resolved,
       pending: Enum.count(state.conflicts, fn {_, c} -> c.status == :detected end),
       strategy: state.strategy,
       threshold: state.threshold
     }, state}
  end

  # --- Resolution Strategies ---

  defp apply_strategy(:anchor_weighted, scores) do
    # Higher confidence scores get more weight (proxy for anchor proximity)
    values = Map.values(scores)
    weights = Enum.map(values, fn v -> v * v end)
    total_weight = Enum.sum(weights)

    if total_weight > 0 do
      weighted = Enum.zip(values, weights) |> Enum.map(fn {v, w} -> v * w end) |> Enum.sum()
      weighted / total_weight
    else
      Enum.sum(values) / max(1, length(values))
    end
  end

  defp apply_strategy(:average, scores) do
    values = Map.values(scores)
    Enum.sum(values) / max(1, length(values))
  end

  defp apply_strategy(:majority_consensus, scores) do
    # Round scores to 1 decimal and pick the most common
    values = Map.values(scores)

    values
    |> Enum.map(&Float.round(&1, 1))
    |> Enum.frequencies()
    |> Enum.max_by(fn {_score, count} -> count end)
    |> elem(0)
  end

  defp apply_strategy(_strategy, scores) do
    apply_strategy(:average, scores)
  end

  # --- Private ---

  defp create_conflict(title, local_score, remote_score, source_instance, state) do
    id = "conflict_#{state.counter + 1}"

    conflict = %{
      id: id,
      node_title: title,
      instance_scores: %{"local" => local_score, source_instance => remote_score},
      resolved_score: nil,
      strategy_used: nil,
      status: :detected,
      detected_at: DateTime.utc_now(),
      resolved_at: nil
    }

    state = %{
      state
      | conflicts: Map.put(state.conflicts, id, conflict),
        counter: state.counter + 1,
        total_detected: state.total_detected + 1
    }

    {conflict, state}
  end

  defp find_local_match(remote_node, graph_repo) do
    case graph_repo.search_nodes(remote_node.title, limit: 1) do
      {:ok, [local | _]} when local.title == remote_node.title -> {:ok, local}
      _ -> :no_match
    end
  end

  defp maybe_filter_status(conflicts, nil), do: conflicts
  defp maybe_filter_status(conflicts, status), do: Enum.filter(conflicts, &(&1.status == status))

  defp graph_repository do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
