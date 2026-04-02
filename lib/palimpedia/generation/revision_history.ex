defmodule Palimpedia.Generation.RevisionHistory do
  @moduledoc """
  Tracks document revision history.

  Every revision records: which node was revised, what triggered it,
  the old and new content, and a simple diff summary.
  """

  use GenServer

  @type revision :: %{
          id: String.t(),
          node_id: integer(),
          node_title: String.t(),
          trigger: trigger(),
          old_content: String.t() | nil,
          new_content: String.t() | nil,
          old_confidence: float(),
          new_confidence: float(),
          diff_summary: String.t(),
          revised_at: DateTime.t()
        }

  @type trigger :: :contradiction | :anchor_update | :staleness | :manual

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Records a revision."
  def record(
        node_id,
        node_title,
        trigger,
        old_content,
        new_content,
        old_confidence,
        new_confidence
      ) do
    GenServer.call(
      __MODULE__,
      {:record, node_id, node_title, trigger, old_content, new_content, old_confidence,
       new_confidence}
    )
  end

  @doc "Returns all revisions for a node, newest first."
  def history_for(node_id) do
    GenServer.call(__MODULE__, {:history_for, node_id})
  end

  @doc "Returns recent revisions across all nodes."
  def recent(limit \\ 20) do
    GenServer.call(__MODULE__, {:recent, limit})
  end

  @doc "Returns revision counts by trigger type."
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # --- GenServer ---

  @impl true
  def init(_opts) do
    {:ok, %{revisions: [], counter: 0}}
  end

  @impl true
  def handle_call(
        {:record, node_id, node_title, trigger, old_content, new_content, old_conf, new_conf},
        _from,
        state
      ) do
    diff_summary = compute_diff(old_content, new_content, old_conf, new_conf)

    revision = %{
      id: "rev_#{state.counter + 1}",
      node_id: node_id,
      node_title: node_title,
      trigger: trigger,
      old_content: old_content,
      new_content: new_content,
      old_confidence: old_conf,
      new_confidence: new_conf,
      diff_summary: diff_summary,
      revised_at: DateTime.utc_now()
    }

    state = %{state | revisions: [revision | state.revisions], counter: state.counter + 1}
    {:reply, {:ok, revision}, state}
  end

  @impl true
  def handle_call({:history_for, node_id}, _from, state) do
    history =
      state.revisions
      |> Enum.filter(&(&1.node_id == node_id))
      |> Enum.sort_by(& &1.revised_at, {:desc, DateTime})

    {:reply, history, state}
  end

  @impl true
  def handle_call({:recent, limit}, _from, state) do
    recent = Enum.take(state.revisions, limit)
    {:reply, recent, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    by_trigger =
      state.revisions
      |> Enum.group_by(& &1.trigger)
      |> Enum.map(fn {trigger, revs} -> {trigger, length(revs)} end)
      |> Map.new()

    {:reply, %{total: length(state.revisions), by_trigger: by_trigger}, state}
  end

  defp compute_diff(old_content, new_content, old_conf, new_conf) do
    content_changed = old_content != new_content
    conf_delta = Float.round((new_conf - old_conf) * 1.0, 4)

    parts = []
    parts = if content_changed, do: ["content revised" | parts], else: parts

    parts =
      cond do
        conf_delta > 0 -> ["confidence +#{conf_delta}" | parts]
        conf_delta < 0 -> ["confidence #{conf_delta}" | parts]
        true -> parts
      end

    if parts == [], do: "no changes", else: Enum.join(Enum.reverse(parts), ", ")
  end
end
