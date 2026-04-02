defmodule Palimpedia.Review.Queue do
  @moduledoc """
  Human review queue for generated documents.

  Documents enter the queue when they exceed a confidence threshold
  or receive high traffic volume. Reviewers can approve (promotes
  confidence), reject (triggers regeneration), or flag for further
  investigation.

  ## Configuration

      config :palimpedia, Palimpedia.Review.Queue,
        confidence_threshold: 0.7,
        traffic_threshold: 10
  """

  use GenServer

  require Logger

  @type review_item :: %{
          id: String.t(),
          node_id: integer(),
          node_title: String.t(),
          reason: :high_confidence | :high_traffic | :manual,
          confidence: float(),
          status: :pending | :approved | :rejected | :flagged,
          submitted_at: DateTime.t(),
          reviewed_at: DateTime.t() | nil,
          reviewer_note: String.t() | nil
        }

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Submits a node for human review.
  Returns the review item if accepted, or :already_queued if duplicate.
  """
  def submit(node_id, node_title, reason, opts \\ []) do
    GenServer.call(__MODULE__, {:submit, node_id, node_title, reason, opts})
  end

  @doc """
  Checks if a generated node should enter the review queue based on
  confidence threshold and traffic. Auto-submits if criteria are met.
  """
  def check_and_submit(node, opts \\ []) do
    config = Application.get_env(:palimpedia, __MODULE__, [])
    confidence_threshold = Keyword.get(config, :confidence_threshold, 0.7)
    traffic_threshold = Keyword.get(config, :traffic_threshold, 10)

    traffic = Keyword.get(opts, :traffic_count, 0)

    cond do
      node.node_type == :anchor ->
        :skip

      node.confidence >= confidence_threshold ->
        submit(node.id, node.title, :high_confidence)

      traffic >= traffic_threshold ->
        submit(node.id, node.title, :high_traffic)

      true ->
        :skip
    end
  end

  @doc "Returns all pending review items, ordered by submission time."
  def list_pending do
    GenServer.call(__MODULE__, :list_pending)
  end

  @doc "Returns a single review item by ID."
  def get(review_id) do
    GenServer.call(__MODULE__, {:get, review_id})
  end

  @doc "Approves a review item. Boosts the node's confidence."
  def approve(review_id, opts \\ []) do
    GenServer.call(__MODULE__, {:decide, review_id, :approved, opts})
  end

  @doc "Rejects a review item. Triggers regeneration."
  def reject(review_id, opts \\ []) do
    GenServer.call(__MODULE__, {:decide, review_id, :rejected, opts})
  end

  @doc "Flags a review item for further investigation."
  def flag(review_id, opts \\ []) do
    GenServer.call(__MODULE__, {:decide, review_id, :flagged, opts})
  end

  @doc "Returns review queue metrics."
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # --- GenServer ---

  @impl true
  def init(_opts) do
    table = :ets.new(:review_queue, [:set, :private])

    {:ok,
     %{
       table: table,
       counter: 0,
       total_approved: 0,
       total_rejected: 0,
       total_flagged: 0,
       review_times: []
     }}
  end

  @impl true
  def handle_call({:submit, node_id, node_title, reason, _opts}, _from, state) do
    # Check for duplicate
    already_queued =
      :ets.foldl(
        fn {_id, item}, found ->
          found or (item.node_id == node_id and item.status == :pending)
        end,
        false,
        state.table
      )

    if already_queued do
      {:reply, {:ok, :already_queued}, state}
    else
      item = %{
        id: "review_#{state.counter + 1}",
        node_id: node_id,
        node_title: node_title,
        reason: reason,
        confidence: 0.0,
        status: :pending,
        submitted_at: DateTime.utc_now(),
        reviewed_at: nil,
        reviewer_note: nil
      }

      :ets.insert(state.table, {item.id, item})
      state = %{state | counter: state.counter + 1}

      Logger.info(
        "Review submitted: #{item.id} for node #{node_id} (#{node_title}) reason=#{reason}"
      )

      {:reply, {:ok, item}, state}
    end
  end

  @impl true
  def handle_call(:list_pending, _from, state) do
    items =
      :ets.foldl(
        fn {_id, item}, acc ->
          if item.status == :pending, do: [item | acc], else: acc
        end,
        [],
        state.table
      )
      |> Enum.sort_by(& &1.submitted_at, {:asc, DateTime})

    {:reply, items, state}
  end

  @impl true
  def handle_call({:get, review_id}, _from, state) do
    case :ets.lookup(state.table, review_id) do
      [{^review_id, item}] -> {:reply, {:ok, item}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:decide, review_id, decision, opts}, _from, state) do
    case :ets.lookup(state.table, review_id) do
      [{^review_id, item}] ->
        now = DateTime.utc_now()

        updated = %{
          item
          | status: decision,
            reviewed_at: now,
            reviewer_note: Keyword.get(opts, :note)
        }

        :ets.insert(state.table, {review_id, updated})

        latency_ms = DateTime.diff(now, item.submitted_at, :millisecond)

        state =
          case decision do
            :approved ->
              %{
                state
                | total_approved: state.total_approved + 1,
                  review_times: [latency_ms | state.review_times]
              }

            :rejected ->
              %{
                state
                | total_rejected: state.total_rejected + 1,
                  review_times: [latency_ms | state.review_times]
              }

            :flagged ->
              %{state | total_flagged: state.total_flagged + 1}
          end

        {:reply, {:ok, updated}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    pending =
      :ets.foldl(
        fn {_id, item}, acc -> if item.status == :pending, do: acc + 1, else: acc end,
        0,
        state.table
      )

    total_reviewed = state.total_approved + state.total_rejected

    approval_rate =
      if total_reviewed > 0, do: state.total_approved / total_reviewed, else: nil

    avg_latency_ms =
      if state.review_times != [] do
        Enum.sum(state.review_times) / length(state.review_times)
      else
        nil
      end

    {:reply,
     %{
       pending: pending,
       total_approved: state.total_approved,
       total_rejected: state.total_rejected,
       total_flagged: state.total_flagged,
       approval_rate: approval_rate,
       avg_latency_ms: avg_latency_ms
     }, state}
  end
end
