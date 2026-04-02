defmodule Palimpedia.Export.Snapshot do
  @moduledoc """
  Manages graph snapshots: scheduled exports, versioning, and diffs.
  """

  use GenServer

  alias Palimpedia.Export.{RDF, JsonLD}

  require Logger

  @type snapshot :: %{
          id: String.t(),
          version: non_neg_integer(),
          format: :rdf | :json_ld,
          node_count: non_neg_integer(),
          edge_count: non_neg_integer(),
          created_at: DateTime.t(),
          size_bytes: non_neg_integer()
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Creates a snapshot of the full graph in the specified format."
  def create(format, opts \\ []) when format in [:rdf, :json_ld] do
    GenServer.call(__MODULE__, {:create, format, opts}, 60_000)
  end

  @doc "Returns metadata for all snapshots."
  def list_snapshots do
    GenServer.call(__MODULE__, :list)
  end

  @doc "Returns a specific snapshot's content."
  def get_snapshot(snapshot_id) do
    GenServer.call(__MODULE__, {:get, snapshot_id})
  end

  @doc "Returns a diff summary between two snapshot versions."
  def diff(snapshot_id_a, snapshot_id_b) do
    GenServer.call(__MODULE__, {:diff, snapshot_id_a, snapshot_id_b})
  end

  # --- GenServer ---

  @impl true
  def init(_opts) do
    {:ok, %{snapshots: %{}, counter: 0}}
  end

  @impl true
  def handle_call({:create, format, opts}, _from, state) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())

    case fetch_full_graph(graph_repo) do
      {:ok, nodes, edges} ->
        content =
          case format do
            :rdf -> RDF.export(nodes, edges)
            :json_ld -> JsonLD.export(nodes, edges)
          end

        version = state.counter + 1
        snapshot_id = "snapshot_v#{version}_#{format}"

        metadata = %{
          id: snapshot_id,
          version: version,
          format: format,
          node_count: length(nodes),
          edge_count: length(edges),
          created_at: DateTime.utc_now(),
          size_bytes: byte_size(content)
        }

        state = %{
          state
          | snapshots: Map.put(state.snapshots, snapshot_id, {metadata, content}),
            counter: version
        }

        Logger.info(
          "Snapshot created: #{snapshot_id} (#{length(nodes)} nodes, #{byte_size(content)} bytes)"
        )

        {:reply, {:ok, metadata}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    metadata =
      state.snapshots
      |> Map.values()
      |> Enum.map(fn {meta, _content} -> meta end)
      |> Enum.sort_by(& &1.version, :desc)

    {:reply, metadata, state}
  end

  @impl true
  def handle_call({:get, snapshot_id}, _from, state) do
    case Map.get(state.snapshots, snapshot_id) do
      {metadata, content} -> {:reply, {:ok, metadata, content}, state}
      nil -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:diff, id_a, id_b}, _from, state) do
    with {meta_a, _} <- Map.get(state.snapshots, id_a),
         {meta_b, _} <- Map.get(state.snapshots, id_b) do
      diff = %{
        version_a: meta_a.version,
        version_b: meta_b.version,
        node_delta: meta_b.node_count - meta_a.node_count,
        edge_delta: meta_b.edge_count - meta_a.edge_count,
        size_delta: meta_b.size_bytes - meta_a.size_bytes,
        time_delta_seconds: DateTime.diff(meta_b.created_at, meta_a.created_at, :second)
      }

      {:reply, {:ok, diff}, state}
    else
      nil -> {:reply, {:error, :not_found}, state}
    end
  end

  defp fetch_full_graph(graph_repo) do
    case graph_repo.search_nodes("", limit: 50_000) do
      {:ok, nodes} ->
        all_edges =
          nodes
          |> Enum.take(100)
          |> Enum.flat_map(fn node ->
            case graph_repo.subgraph(node.id, 1) do
              {:ok, _nodes, edges} -> edges
              _ -> []
            end
          end)
          |> Enum.uniq_by(& &1.id)

        {:ok, nodes, all_edges}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp graph_repository do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
