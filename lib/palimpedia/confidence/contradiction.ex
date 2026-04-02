defmodule Palimpedia.Confidence.Contradiction do
  @moduledoc """
  Contradiction store and detection.

  Manages contradictions between documents — flagged by users (Tier 3)
  or detected automatically by claim comparison. Each contradiction
  triggers a confidence review for affected nodes.

  Implemented as a GenServer with ETS storage.
  """

  use GenServer

  require Logger

  @type contradiction :: %{
          id: String.t(),
          node_a_id: integer(),
          node_b_id: integer(),
          description: String.t(),
          severity: severity(),
          status: status(),
          flagged_by: :system | :user,
          flagged_at: DateTime.t()
        }

  @type status :: :open | :reviewing | :resolved | :dismissed
  @type severity :: :low | :medium | :high

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Flags a contradiction between two nodes.
  Returns the created contradiction record.
  """
  def flag(node_a_id, node_b_id, description, opts \\ []) do
    GenServer.call(__MODULE__, {:flag, node_a_id, node_b_id, description, opts})
  end

  @doc "Returns all open contradictions, optionally filtered by node ID."
  def list_open(opts \\ []) do
    GenServer.call(__MODULE__, {:list_open, opts})
  end

  @doc "Returns the count of open contradictions for a given node."
  def count_for_node(node_id) do
    GenServer.call(__MODULE__, {:count_for_node, node_id})
  end

  @doc "Resolves a contradiction by ID."
  def resolve(contradiction_id, resolution) when resolution in [:confirmed, :dismissed] do
    GenServer.call(__MODULE__, {:resolve, contradiction_id, resolution})
  end

  @doc "Returns all contradictions (any status)."
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  # --- GenServer ---

  @impl true
  def init(_opts) do
    table = :ets.new(:contradictions, [:set, :private])
    {:ok, %{table: table, counter: 0}}
  end

  @impl true
  def handle_call({:flag, node_a_id, node_b_id, description, opts}, _from, state) do
    severity = Keyword.get(opts, :severity, :medium)
    flagged_by = Keyword.get(opts, :flagged_by, :user)

    contradiction = %{
      id: "contradiction_#{state.counter + 1}",
      node_a_id: node_a_id,
      node_b_id: node_b_id,
      description: description,
      severity: severity,
      status: :open,
      flagged_by: flagged_by,
      flagged_at: DateTime.utc_now()
    }

    :ets.insert(state.table, {contradiction.id, contradiction})
    state = %{state | counter: state.counter + 1}

    Logger.info(
      "Contradiction flagged: #{contradiction.id} between nodes #{node_a_id} and #{node_b_id} (#{severity})"
    )

    {:reply, {:ok, contradiction}, state}
  end

  @impl true
  def handle_call({:list_open, opts}, _from, state) do
    node_id = Keyword.get(opts, :node_id)

    results =
      :ets.foldl(
        fn {_id, c}, acc ->
          if c.status == :open and matches_node_filter?(c, node_id) do
            [c | acc]
          else
            acc
          end
        end,
        [],
        state.table
      )
      |> Enum.sort_by(& &1.flagged_at, {:desc, DateTime})

    {:reply, {:ok, results}, state}
  end

  @impl true
  def handle_call({:count_for_node, node_id}, _from, state) do
    count =
      :ets.foldl(
        fn {_id, c}, acc ->
          if c.status == :open and (c.node_a_id == node_id or c.node_b_id == node_id) do
            acc + 1
          else
            acc
          end
        end,
        0,
        state.table
      )

    {:reply, count, state}
  end

  @impl true
  def handle_call({:resolve, contradiction_id, resolution}, _from, state) do
    case :ets.lookup(state.table, contradiction_id) do
      [{^contradiction_id, contradiction}] ->
        new_status = if resolution == :confirmed, do: :resolved, else: :dismissed
        updated = %{contradiction | status: new_status}
        :ets.insert(state.table, {contradiction_id, updated})
        {:reply, {:ok, updated}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    all =
      :ets.foldl(fn {_id, c}, acc -> [c | acc] end, [], state.table)
      |> Enum.sort_by(& &1.flagged_at, {:desc, DateTime})

    {:reply, {:ok, all}, state}
  end

  defp matches_node_filter?(_, nil), do: true

  defp matches_node_filter?(c, node_id) do
    c.node_a_id == node_id or c.node_b_id == node_id
  end
end
