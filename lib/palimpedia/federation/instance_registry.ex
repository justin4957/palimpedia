defmodule Palimpedia.Federation.InstanceRegistry do
  @moduledoc """
  Registry of known federated Palimpedia instances.

  Tracks peer instances with their URLs, trust levels, and sync status.
  """

  use GenServer

  require Logger

  @type peer :: %{
          instance_id: String.t(),
          url: String.t(),
          name: String.t(),
          trust_level: :trusted | :verified | :untrusted,
          last_sync_at: DateTime.t() | nil,
          registered_at: DateTime.t()
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Registers a peer instance."
  def register_peer(instance_id, url, name, opts \\ []) do
    GenServer.call(__MODULE__, {:register, instance_id, url, name, opts})
  end

  @doc "Returns all registered peers."
  def list_peers do
    GenServer.call(__MODULE__, :list)
  end

  @doc "Returns a specific peer by ID."
  def get_peer(instance_id) do
    GenServer.call(__MODULE__, {:get, instance_id})
  end

  @doc "Updates the last sync timestamp for a peer."
  def mark_synced(instance_id) do
    GenServer.call(__MODULE__, {:mark_synced, instance_id})
  end

  @doc "Returns the local instance ID."
  def local_instance_id do
    Application.get_env(:palimpedia, __MODULE__, [])
    |> Keyword.get(:instance_id, generate_instance_id())
  end

  # --- GenServer ---

  @impl true
  def init(_opts) do
    {:ok, %{peers: %{}}}
  end

  @impl true
  def handle_call({:register, instance_id, url, name, opts}, _from, state) do
    trust = Keyword.get(opts, :trust_level, :untrusted)

    peer = %{
      instance_id: instance_id,
      url: url,
      name: name,
      trust_level: trust,
      last_sync_at: nil,
      registered_at: DateTime.utc_now()
    }

    state = %{state | peers: Map.put(state.peers, instance_id, peer)}
    Logger.info("Federation: registered peer #{instance_id} (#{name}) at #{url}")
    {:reply, {:ok, peer}, state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    peers = Map.values(state.peers) |> Enum.sort_by(& &1.registered_at, {:asc, DateTime})
    {:reply, peers, state}
  end

  @impl true
  def handle_call({:get, instance_id}, _from, state) do
    case Map.get(state.peers, instance_id) do
      nil -> {:reply, {:error, :not_found}, state}
      peer -> {:reply, {:ok, peer}, state}
    end
  end

  @impl true
  def handle_call({:mark_synced, instance_id}, _from, state) do
    case Map.get(state.peers, instance_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      peer ->
        updated = %{peer | last_sync_at: DateTime.utc_now()}
        state = %{state | peers: Map.put(state.peers, instance_id, updated)}
        {:reply, {:ok, updated}, state}
    end
  end

  defp generate_instance_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
