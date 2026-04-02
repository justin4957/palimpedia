defmodule Palimpedia.Federation.Sync do
  @moduledoc """
  Subgraph export, import, and synchronization between federated instances.
  """

  alias Palimpedia.Federation.{Protocol, InstanceRegistry}
  alias Palimpedia.Graph.Edge

  require Logger

  @type export_result :: %{
          nodes_exported: non_neg_integer(),
          edges_exported: non_neg_integer(),
          message: String.t()
        }

  @type import_result :: %{
          nodes_imported: non_neg_integer(),
          edges_imported: non_neg_integer(),
          skipped: non_neg_integer(),
          errors: [term()]
        }

  @doc """
  Exports a subgraph as a federation message ready to send to a peer.
  """
  def export_subgraph(center_node_id, opts \\ []) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())
    hops = Keyword.get(opts, :hops, 2)

    case graph_repo.subgraph(center_node_id, hops) do
      {:ok, nodes, edges} ->
        payload = Protocol.serialize_subgraph(nodes, edges)
        instance_id = InstanceRegistry.local_instance_id()

        case Protocol.encode(:subgraph_share, payload, instance_id) do
          {:ok, json} ->
            {:ok,
             %{
               nodes_exported: length(nodes),
               edges_exported: length(edges),
               message: json
             }}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Imports a federation message, merging the subgraph into the local graph.
  Nodes are matched by title — duplicates are skipped.
  """
  def import_message(json, opts \\ []) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())

    with {:ok, message} <- Protocol.decode(json),
         {:ok, nodes, edges} <- Protocol.deserialize_subgraph(message.payload) do
      # Import nodes (skip duplicates by title)
      {imported_nodes, node_id_map, skipped, node_errors} = import_nodes(nodes, graph_repo)

      # Import edges using the title-to-id map
      {imported_edges, edge_errors} = import_edges(edges, node_id_map, graph_repo)

      # Mark the source instance as synced
      if message.source_instance do
        InstanceRegistry.mark_synced(message.source_instance)
      end

      Logger.info(
        "Federation import from #{message.source_instance}: #{imported_nodes} nodes, #{imported_edges} edges"
      )

      {:ok,
       %{
         nodes_imported: imported_nodes,
         edges_imported: imported_edges,
         skipped: skipped,
         errors: node_errors ++ edge_errors
       }}
    end
  end

  @doc """
  Exports an edge assertion as a federation message for forwarding to peers.
  """
  def export_edge_assertion(source_title, target_title, edge_type, opts \\ []) do
    payload = %{
      source_title: source_title,
      target_title: target_title,
      edge_type: Atom.to_string(edge_type),
      confidence: Keyword.get(opts, :confidence, 0.5),
      provenance: Keyword.get(opts, :provenance, [])
    }

    instance_id = InstanceRegistry.local_instance_id()
    Protocol.encode(:edge_assertion, payload, instance_id)
  end

  # --- Private ---

  defp import_nodes(nodes, graph_repo) do
    Enum.reduce(nodes, {0, %{}, 0, []}, fn node, {count, id_map, skipped, errors} ->
      # Check if node with same title already exists
      case graph_repo.search_nodes(node.title, limit: 1) do
        {:ok, [existing | _]} when existing.title == node.title ->
          {count, Map.put(id_map, node.title, existing.id), skipped + 1, errors}

        _ ->
          case graph_repo.insert_node(node) do
            {:ok, inserted} ->
              {count + 1, Map.put(id_map, node.title, inserted.id), skipped, errors}

            {:error, reason} ->
              {count, id_map, skipped, [{:node_import_failed, node.title, reason} | errors]}
          end
      end
    end)
  end

  defp import_edges(edges, node_id_map, graph_repo) do
    Enum.reduce(edges, {0, []}, fn edge_data, {count, errors} ->
      source_id = Map.get(node_id_map, edge_data.source_title)
      target_id = Map.get(node_id_map, edge_data.target_title)

      if source_id && target_id do
        edge = %Edge{
          source_id: source_id,
          target_id: target_id,
          edge_type: edge_data.edge_type,
          confidence: edge_data.confidence,
          provenance: edge_data.provenance
        }

        case graph_repo.insert_edge(edge) do
          {:ok, _} -> {count + 1, errors}
          {:error, reason} -> {count, [{:edge_import_failed, edge_data, reason} | errors]}
        end
      else
        {count, errors}
      end
    end)
  end

  defp graph_repository do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
