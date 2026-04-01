defmodule Palimpedia.Anchor.Ingestion do
  @moduledoc """
  Pipeline for ingesting anchor corpus data from external sources.

  Orchestrates: adapter fetch -> entity extraction -> graph insertion.
  Handles batch processing with progress tracking and error recovery.
  """

  alias Palimpedia.Anchor.Adapter
  alias Palimpedia.Graph.Edge

  require Logger

  @type ingestion_result :: %{
          nodes_created: non_neg_integer(),
          edges_created: non_neg_integer(),
          errors: [term()]
        }

  @doc """
  Ingests entities from a source adapter by their identifiers.
  Creates anchor nodes and typed edges in the graph.

  ## Options
    * `:batch_size` - Number of entities to process per batch (default: 50)
    * `:graph_repo` - Graph repository module (default: configured repo)
  """
  def ingest_entities(adapter_module, identifiers, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 50)
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())

    identifiers
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce(empty_result(), fn batch, accumulated_result ->
      batch_result = ingest_batch(adapter_module, batch, graph_repo, opts)
      merge_results(accumulated_result, batch_result)
    end)
  end

  @doc """
  Ingests entities from a search query against a source adapter.

  ## Options
    * `:limit` - Maximum entities to ingest (default: 100)
    * `:graph_repo` - Graph repository module (default: configured repo)
  """
  def ingest_search(adapter_module, query, opts \\ []) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())

    case adapter_module.search(query, opts) do
      {:ok, fetch_result} ->
        insert_fetch_result(fetch_result, graph_repo)

      {:error, reason} ->
        Logger.error("Search ingestion failed for #{inspect(query)}: #{inspect(reason)}")
        {:ok, %{empty_result() | errors: [{:search_failed, query, reason}]}}
    end
  end

  @doc """
  Inserts pre-fetched adapter results into the graph.
  Returns counts of created nodes and edges, plus any errors.
  """
  def insert_fetch_result(fetch_result, graph_repo) do
    node_results = insert_entities(fetch_result.entities, graph_repo)

    edge_results =
      insert_relationships(fetch_result.relationships, node_results.id_map, graph_repo)

    {:ok,
     %{
       nodes_created: node_results.created,
       edges_created: edge_results.created,
       errors: node_results.errors ++ edge_results.errors
     }}
  end

  # --- Private ---

  defp ingest_batch(adapter_module, identifiers, graph_repo, opts) do
    case adapter_module.fetch_entities(identifiers, opts) do
      {:ok, fetch_result} ->
        case insert_fetch_result(fetch_result, graph_repo) do
          {:ok, result} ->
            Logger.info(
              "Batch ingested: #{result.nodes_created} nodes, #{result.edges_created} edges"
            )

            result
        end

      {:error, reason} ->
        Logger.error("Batch fetch failed: #{inspect(reason)}")
        %{empty_result() | errors: [{:batch_failed, identifiers, reason}]}
    end
  end

  defp insert_entities(entities, graph_repo) do
    nodes = Adapter.entities_to_nodes(entities)

    Enum.reduce(nodes, %{created: 0, errors: [], id_map: %{}}, fn node, acc ->
      case graph_repo.insert_node(node) do
        {:ok, inserted} ->
          source_id = hd(inserted.provenance)

          %{
            acc
            | created: acc.created + 1,
              id_map: Map.put(acc.id_map, source_id, inserted.id)
          }

        {:error, reason} ->
          %{acc | errors: [{:node_insert_failed, node.title, reason} | acc.errors]}
      end
    end)
  end

  defp insert_relationships(relationships, source_to_graph_id, graph_repo) do
    Enum.reduce(relationships, %{created: 0, errors: []}, fn rel, acc ->
      source_graph_id = Map.get(source_to_graph_id, rel.source_id)
      target_graph_id = Map.get(source_to_graph_id, rel.target_id)

      cond do
        is_nil(source_graph_id) ->
          %{acc | errors: [{:missing_source_node, rel.source_id} | acc.errors]}

        is_nil(target_graph_id) ->
          %{acc | errors: [{:missing_target_node, rel.target_id} | acc.errors]}

        true ->
          edge = %Edge{
            source_id: source_graph_id,
            target_id: target_graph_id,
            edge_type: rel.edge_type,
            confidence: rel.confidence,
            provenance: [rel.source_id, rel.target_id]
          }

          case graph_repo.insert_edge(edge) do
            {:ok, _} -> %{acc | created: acc.created + 1}
            {:error, reason} -> %{acc | errors: [{:edge_insert_failed, rel, reason} | acc.errors]}
          end
      end
    end)
  end

  defp empty_result do
    %{nodes_created: 0, edges_created: 0, errors: []}
  end

  defp merge_results(a, b) do
    %{
      nodes_created: a.nodes_created + b.nodes_created,
      edges_created: a.edges_created + b.edges_created,
      errors: a.errors ++ b.errors
    }
  end

  defp graph_repository do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
