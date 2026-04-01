defmodule Palimpedia.Confidence.Updater do
  @moduledoc """
  Batch confidence recalculation for nodes affected by graph changes.

  Triggered by:
  - New edges (propagation)
  - Contradiction flags (penalty)
  - Temporal decay sweeps
  - Anchor corpus updates
  """

  alias Palimpedia.Confidence.Scorer
  alias Palimpedia.Graph.Node

  require Logger

  @type update_result :: %{
          updated: non_neg_integer(),
          flagged_for_regrounding: non_neg_integer(),
          errors: [term()]
        }

  @doc """
  Recalculates confidence for a single node using live graph data.
  Persists the updated score and anchor_distance to the graph.
  """
  def recalculate_node(%Node{} = node, graph_repo) do
    case Scorer.score_node(node, graph_repo) do
      {:ok, new_confidence, chain} ->
        new_distance = chain.anchor_distance

        case graph_repo.update_confidence(node.id, new_confidence, new_distance) do
          {:ok, updated_node} ->
            if Scorer.requires_regrounding?(new_distance) do
              Logger.warning(
                "Node #{node.id} (#{node.title}) requires regrounding: distance=#{new_distance}"
              )
            end

            {:ok, updated_node}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Recalculates confidence for all nodes in a subgraph neighborhood.
  Useful after a new edge is added or a contradiction is flagged.
  """
  def recalculate_subgraph(center_node_id, graph_repo, opts \\ []) do
    hops = Keyword.get(opts, :hops, 2)

    with {:ok, nodes, _edges} <- graph_repo.subgraph(center_node_id, hops) do
      # Skip anchor nodes — they always have confidence 1.0
      non_anchor_nodes = Enum.reject(nodes, &(&1.node_type == :anchor))

      result =
        Enum.reduce(non_anchor_nodes, empty_result(), fn node, acc ->
          case recalculate_node(node, graph_repo) do
            {:ok, updated} ->
              acc = %{acc | updated: acc.updated + 1}

              if Scorer.requires_regrounding?(updated.anchor_distance) do
                %{acc | flagged_for_regrounding: acc.flagged_for_regrounding + 1}
              else
                acc
              end

            {:error, reason} ->
              %{acc | errors: [{:recalculate_failed, node.id, reason} | acc.errors]}
          end
        end)

      {:ok, result}
    end
  end

  @doc """
  Finds and flags all ungrounded nodes (anchor_distance > max_hops).
  Returns the list of nodes requiring regrounding.
  """
  def find_regrounding_candidates(graph_repo, opts \\ []) do
    max_hops = Keyword.get(opts, :max_hops, Scorer.max_anchor_hops())
    graph_repo.find_ungrounded(max_hops, opts)
  end

  @doc """
  Applies propagation effects when a new edge is created between two nodes.
  Updates confidence scores for any nodes that benefit from the new connection.
  """
  def apply_edge_propagation(source_node, target_node, graph_repo) do
    updates = Scorer.propagation_effects(source_node, target_node)

    Enum.reduce(updates, empty_result(), fn {node_id, new_confidence, new_distance}, acc ->
      case graph_repo.update_confidence(node_id, new_confidence, new_distance) do
        {:ok, _} -> %{acc | updated: acc.updated + 1}
        {:error, reason} -> %{acc | errors: [{:propagation_failed, node_id, reason} | acc.errors]}
      end
    end)
  end

  defp empty_result do
    %{updated: 0, flagged_for_regrounding: 0, errors: []}
  end
end
