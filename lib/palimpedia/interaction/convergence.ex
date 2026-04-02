defmodule Palimpedia.Interaction.Convergence do
  @moduledoc """
  Convergence detection: clusters independent user assertions toward the same gap.

  "Convergent user prompts — multiple independent users asserting the same gap
  or edge — are treated as high-confidence signals regardless of individual
  trust tier. Convergence is data."

  Tracks assertions by normalized topic, groups by distinct user sources, and
  boosts generation priority proportionally when convergence thresholds are met.

  ## Configuration

      config :palimpedia, Palimpedia.Interaction.Convergence,
        convergence_threshold: 3,
        boost_per_signal: 3.0,
        similarity_threshold: 0.6
  """

  use GenServer

  alias Palimpedia.GapDetection.GenerationQueue

  require Logger

  @type cluster :: %{
          topic: String.t(),
          signals: [signal()],
          distinct_users: MapSet.t(),
          total_signals: non_neg_integer(),
          converged: boolean(),
          first_seen_at: DateTime.t(),
          last_signal_at: DateTime.t()
        }

  @type signal :: %{
          user_id: String.t() | nil,
          tier: atom(),
          timestamp: DateTime.t(),
          raw_input: String.t()
        }

  @convergence_threshold 3
  @boost_per_signal 3.0

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a user assertion and checks for convergence.

  Returns:
  - `{:ok, :recorded}` if signal recorded but threshold not yet met
  - `{:ok, :converged, cluster}` if this signal triggered convergence
  - `{:ok, :already_converged, cluster}` if cluster already converged
  """
  def record_signal(topic, tier, opts \\ []) do
    GenServer.call(__MODULE__, {:record, topic, tier, opts})
  end

  @doc "Returns all clusters that have reached convergence."
  def converged_clusters do
    GenServer.call(__MODULE__, :converged)
  end

  @doc "Returns all clusters (converged and not)."
  def all_clusters do
    GenServer.call(__MODULE__, :all)
  end

  @doc "Returns convergence metrics."
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc "Returns the cluster for a specific topic, if it exists."
  def get_cluster(topic) do
    GenServer.call(__MODULE__, {:get, topic})
  end

  # --- GenServer ---

  @impl true
  def init(_opts) do
    {:ok, %{clusters: %{}}}
  end

  @impl true
  def handle_call({:record, raw_topic, tier, opts}, _from, state) do
    user_id = Keyword.get(opts, :user_id)
    topic = normalize_topic(raw_topic)

    signal = %{
      user_id: user_id,
      tier: tier,
      timestamp: DateTime.utc_now(),
      raw_input: raw_topic
    }

    cluster = get_or_create_cluster(state, topic)
    cluster = add_signal(cluster, signal)

    was_converged = cluster.converged
    cluster = check_convergence(cluster)

    state = %{state | clusters: Map.put(state.clusters, topic, cluster)}

    result =
      cond do
        cluster.converged and not was_converged ->
          apply_convergence_boost(cluster)

          Logger.info(
            "Convergence detected for '#{topic}': #{cluster.total_signals} signals from #{MapSet.size(cluster.distinct_users)} users"
          )

          {:ok, :converged, sanitize_cluster(cluster)}

        cluster.converged ->
          # Already converged — still boost proportionally
          apply_incremental_boost(cluster)
          {:ok, :already_converged, sanitize_cluster(cluster)}

        true ->
          {:ok, :recorded}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:converged, _from, state) do
    converged =
      state.clusters
      |> Enum.filter(fn {_topic, cluster} -> cluster.converged end)
      |> Enum.map(fn {_topic, cluster} -> sanitize_cluster(cluster) end)
      |> Enum.sort_by(& &1.total_signals, :desc)

    {:reply, converged, state}
  end

  @impl true
  def handle_call(:all, _from, state) do
    all =
      state.clusters
      |> Enum.map(fn {_topic, cluster} -> sanitize_cluster(cluster) end)
      |> Enum.sort_by(& &1.total_signals, :desc)

    {:reply, all, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    total_clusters = map_size(state.clusters)
    converged_count = Enum.count(state.clusters, fn {_, c} -> c.converged end)

    total_signals =
      state.clusters
      |> Enum.map(fn {_, c} -> c.total_signals end)
      |> Enum.sum()

    {:reply,
     %{
       total_clusters: total_clusters,
       converged_clusters: converged_count,
       total_signals: total_signals,
       convergence_rate: if(total_clusters > 0, do: converged_count / total_clusters, else: 0.0)
     }, state}
  end

  @impl true
  def handle_call({:get, topic}, _from, state) do
    normalized = normalize_topic(topic)

    case Map.get(state.clusters, normalized) do
      nil -> {:reply, {:error, :not_found}, state}
      cluster -> {:reply, {:ok, sanitize_cluster(cluster)}, state}
    end
  end

  # --- Private ---

  defp get_or_create_cluster(state, topic) do
    Map.get(state.clusters, topic, %{
      topic: topic,
      signals: [],
      distinct_users: MapSet.new(),
      total_signals: 0,
      converged: false,
      first_seen_at: DateTime.utc_now(),
      last_signal_at: DateTime.utc_now()
    })
  end

  defp add_signal(cluster, signal) do
    distinct_users =
      if signal.user_id do
        MapSet.put(cluster.distinct_users, signal.user_id)
      else
        cluster.distinct_users
      end

    %{
      cluster
      | signals: [signal | cluster.signals],
        distinct_users: distinct_users,
        total_signals: cluster.total_signals + 1,
        last_signal_at: signal.timestamp
    }
  end

  defp check_convergence(cluster) do
    distinct_count = MapSet.size(cluster.distinct_users)

    if distinct_count >= @convergence_threshold do
      %{cluster | converged: true}
    else
      cluster
    end
  end

  defp apply_convergence_boost(cluster) do
    if Process.whereis(GenerationQueue) do
      boost = MapSet.size(cluster.distinct_users) * @boost_per_signal
      GenerationQueue.boost(cluster.topic, boost)
    end
  end

  defp apply_incremental_boost(_cluster) do
    # Each additional signal after convergence adds a smaller boost
    # (handled by the normal Handler.boost_queue flow)
    :ok
  end

  defp normalize_topic(topic) do
    topic
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[^a-z0-9\s]+/, "")
    |> String.replace(~r/\s+/, " ")
  end

  defp sanitize_cluster(cluster) do
    %{
      topic: cluster.topic,
      total_signals: cluster.total_signals,
      distinct_users: MapSet.size(cluster.distinct_users),
      converged: cluster.converged,
      first_seen_at: cluster.first_seen_at,
      last_signal_at: cluster.last_signal_at,
      signals:
        Enum.map(cluster.signals, fn s ->
          %{user_id: s.user_id, tier: s.tier, timestamp: s.timestamp}
        end)
    }
  end
end
