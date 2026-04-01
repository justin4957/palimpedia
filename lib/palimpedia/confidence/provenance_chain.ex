defmodule Palimpedia.Confidence.ProvenanceChain do
  @moduledoc """
  Traces provenance chains from any node back to anchor sources.

  Detects citation loops (closed clusters with no anchor grounding)
  and computes the shortest anchor distance for confidence scoring.
  """

  alias Palimpedia.Graph.Node

  @type chain_result :: %{
          node_id: integer(),
          anchor_sources: [Node.t()],
          anchor_distance: non_neg_integer() | nil,
          grounded: boolean(),
          citation_loop: boolean()
        }

  @doc """
  Traces provenance for a node by querying the graph for reachable anchor sources.

  Returns anchor sources, shortest distance, and whether the node is grounded
  (has a path to at least one anchor within max_hops).
  """
  def trace(node_id, graph_repo, opts \\ []) do
    max_hops = Keyword.get(opts, :max_hops, 10)

    with {:ok, distance} <- graph_repo.shortest_anchor_distance(node_id, max_hops),
         {:ok, anchors} <- graph_repo.anchor_sources(node_id, max_hops) do
      grounded = distance != nil
      citation_loop = !grounded and has_incoming_edges?(node_id, graph_repo)

      {:ok,
       %{
         node_id: node_id,
         anchor_sources: anchors,
         anchor_distance: distance,
         grounded: grounded,
         citation_loop: citation_loop
       }}
    end
  end

  @doc """
  Traces provenance for multiple nodes, returning a map of node_id -> chain_result.
  """
  def trace_batch(node_ids, graph_repo, opts \\ []) do
    results =
      Enum.reduce(node_ids, %{}, fn node_id, acc ->
        case trace(node_id, graph_repo, opts) do
          {:ok, result} -> Map.put(acc, node_id, result)
          {:error, _} -> acc
        end
      end)

    {:ok, results}
  end

  @doc """
  Checks if a node's provenance chain contains a citation loop —
  a cluster of generated nodes referencing each other with no anchor path.
  """
  def citation_loop?(node_id, graph_repo, opts \\ []) do
    case trace(node_id, graph_repo, opts) do
      {:ok, %{citation_loop: loop}} -> loop
      _ -> false
    end
  end

  defp has_incoming_edges?(node_id, graph_repo) do
    case graph_repo.subgraph(node_id, 1) do
      {:ok, _nodes, edges} -> length(edges) > 0
      _ -> false
    end
  end
end
