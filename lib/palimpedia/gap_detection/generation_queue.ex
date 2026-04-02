defmodule Palimpedia.GapDetection.GenerationQueue do
  @moduledoc """
  Priority queue for documents that need to be generated.

  Entries are scored by: relational pressure + user demand + confidence delta.
  Higher-priority gaps are dequeued first. User demand signals boost priority
  for existing entries. Budget caps limit generation throughput per time window.

  Implemented as a GenServer with ETS-backed storage. Can be migrated to
  Oban when a Postgres dependency is added.

  ## Configuration

      config :palimpedia, Palimpedia.GapDetection.GenerationQueue,
        budget_per_hour: 100,
        demand_boost: 2.0
  """

  use GenServer

  require Logger

  @type queue_entry :: %{
          id: String.t(),
          gap_type: atom(),
          priority: float(),
          context_node_ids: [integer()],
          suggested_title: String.t() | nil,
          demand_count: non_neg_integer(),
          inserted_at: DateTime.t(),
          status: :pending | :processing | :completed | :failed
        }

  @type queue_stats :: %{
          depth: non_neg_integer(),
          processing: non_neg_integer(),
          completed_this_hour: non_neg_integer(),
          budget_remaining: non_neg_integer() | :unlimited,
          oldest_entry: DateTime.t() | nil
        }

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Enqueues a gap for document generation. Returns the entry with assigned ID."
  def enqueue(gap) do
    GenServer.call(__MODULE__, {:enqueue, gap})
  end

  @doc "Enqueues multiple gaps at once (e.g., from an analysis run)."
  def enqueue_batch(gaps) when is_list(gaps) do
    GenServer.call(__MODULE__, {:enqueue_batch, gaps})
  end

  @doc "Dequeues the highest-priority pending entry. Returns :empty if queue is empty or budget exhausted."
  def dequeue do
    GenServer.call(__MODULE__, :dequeue)
  end

  @doc """
  Boosts priority for entries matching a suggested title (user demand signal).
  Multiple independent boosts for the same title stack.
  """
  def boost(suggested_title, boost_amount \\ nil) do
    GenServer.call(__MODULE__, {:boost, suggested_title, boost_amount})
  end

  @doc "Marks an entry as completed."
  def complete(entry_id) do
    GenServer.call(__MODULE__, {:set_status, entry_id, :completed})
  end

  @doc "Marks an entry as failed (will not be re-dequeued)."
  def fail(entry_id) do
    GenServer.call(__MODULE__, {:set_status, entry_id, :failed})
  end

  @doc "Returns queue monitoring stats."
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc "Returns all pending entries sorted by priority (descending)."
  def list_pending do
    GenServer.call(__MODULE__, :list_pending)
  end

  @doc "Returns the current queue depth (pending entries only)."
  def depth do
    GenServer.call(__MODULE__, :depth)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    config = Application.get_env(:palimpedia, __MODULE__, [])

    budget_per_hour =
      Keyword.get(config, :budget_per_hour, Keyword.get(opts, :budget_per_hour, 100))

    demand_boost = Keyword.get(config, :demand_boost, Keyword.get(opts, :demand_boost, 2.0))

    table = :ets.new(:generation_queue, [:set, :private])

    state = %{
      table: table,
      budget_per_hour: budget_per_hour,
      demand_boost: demand_boost,
      completed_timestamps: [],
      counter: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, gap}, _from, state) do
    {entry, state} = do_enqueue(gap, state)
    {:reply, {:ok, entry}, state}
  end

  @impl true
  def handle_call({:enqueue_batch, gaps}, _from, state) do
    {entries, state} =
      Enum.reduce(gaps, {[], state}, fn gap, {acc, st} ->
        {entry, st} = do_enqueue(gap, st)
        {[entry | acc], st}
      end)

    {:reply, {:ok, Enum.reverse(entries)}, state}
  end

  @impl true
  def handle_call(:dequeue, _from, state) do
    state = prune_completed_timestamps(state)

    if budget_exhausted?(state) do
      {:reply, {:ok, :budget_exhausted}, state}
    else
      case highest_priority_pending(state) do
        nil ->
          {:reply, {:ok, :empty}, state}

        entry ->
          updated = %{entry | status: :processing}
          :ets.insert(state.table, {entry.id, updated})

          {:reply, {:ok, updated}, state}
      end
    end
  end

  @impl true
  def handle_call({:boost, suggested_title, boost_amount}, _from, state) do
    amount = boost_amount || state.demand_boost

    matched =
      :ets.foldl(
        fn {id, entry}, acc ->
          if entry.status == :pending and match_title?(entry, suggested_title) do
            boosted = %{
              entry
              | priority: entry.priority + amount,
                demand_count: entry.demand_count + 1
            }

            :ets.insert(state.table, {id, boosted})
            acc + 1
          else
            acc
          end
        end,
        0,
        state.table
      )

    {:reply, {:ok, matched}, state}
  end

  @impl true
  def handle_call({:set_status, entry_id, new_status}, _from, state) do
    case :ets.lookup(state.table, entry_id) do
      [{^entry_id, entry}] ->
        updated = %{entry | status: new_status}
        :ets.insert(state.table, {entry_id, updated})

        state =
          if new_status == :completed do
            %{state | completed_timestamps: [DateTime.utc_now() | state.completed_timestamps]}
          else
            state
          end

        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    state = prune_completed_timestamps(state)

    pending = count_by_status(state, :pending)
    processing = count_by_status(state, :processing)
    completed_this_hour = length(state.completed_timestamps)

    budget_remaining =
      if state.budget_per_hour == :unlimited do
        :unlimited
      else
        max(0, state.budget_per_hour - completed_this_hour)
      end

    oldest =
      :ets.foldl(
        fn {_id, entry}, acc ->
          if entry.status == :pending do
            case acc do
              nil ->
                entry.inserted_at

              dt ->
                if DateTime.compare(entry.inserted_at, dt) == :lt, do: entry.inserted_at, else: dt
            end
          else
            acc
          end
        end,
        nil,
        state.table
      )

    {:reply,
     %{
       depth: pending,
       processing: processing,
       completed_this_hour: completed_this_hour,
       budget_remaining: budget_remaining,
       oldest_entry: oldest
     }, state}
  end

  @impl true
  def handle_call(:list_pending, _from, state) do
    entries =
      :ets.foldl(
        fn {_id, entry}, acc ->
          if entry.status == :pending, do: [entry | acc], else: acc
        end,
        [],
        state.table
      )
      |> Enum.sort_by(& &1.priority, :desc)

    {:reply, entries, state}
  end

  @impl true
  def handle_call(:depth, _from, state) do
    {:reply, count_by_status(state, :pending), state}
  end

  # --- Private ---

  defp do_enqueue(gap, state) do
    entry_id = "gap_#{state.counter + 1}"

    context_node_ids =
      case gap do
        %{context: %{node_id: id}} -> [id]
        %{context: %{node_a_id: a, node_b_id: b}} -> [a, b]
        _ -> []
      end

    entry = %{
      id: entry_id,
      gap_type: gap[:gap_type] || :unknown,
      priority: gap[:priority] || 0.0,
      context_node_ids: context_node_ids,
      suggested_title: gap[:suggested_title],
      demand_count: 0,
      inserted_at: DateTime.utc_now(),
      status: :pending
    }

    :ets.insert(state.table, {entry_id, entry})
    state = %{state | counter: state.counter + 1}

    {entry, state}
  end

  defp highest_priority_pending(state) do
    :ets.foldl(
      fn {_id, entry}, acc ->
        if entry.status == :pending do
          case acc do
            nil -> entry
            best -> if entry.priority > best.priority, do: entry, else: best
          end
        else
          acc
        end
      end,
      nil,
      state.table
    )
  end

  defp count_by_status(state, target_status) do
    :ets.foldl(
      fn {_id, entry}, acc ->
        if entry.status == target_status, do: acc + 1, else: acc
      end,
      0,
      state.table
    )
  end

  defp budget_exhausted?(state) do
    state.budget_per_hour != :unlimited and
      length(state.completed_timestamps) >= state.budget_per_hour
  end

  defp prune_completed_timestamps(state) do
    one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second)

    pruned =
      Enum.filter(state.completed_timestamps, fn ts ->
        DateTime.compare(ts, one_hour_ago) == :gt
      end)

    %{state | completed_timestamps: pruned}
  end

  defp match_title?(entry, title) do
    case entry.suggested_title do
      nil -> false
      suggested -> String.downcase(suggested) =~ String.downcase(title)
    end
  end
end
