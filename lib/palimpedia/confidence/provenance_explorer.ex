defmodule Palimpedia.Confidence.ProvenanceExplorer do
  @moduledoc """
  Provenance explorer: trace any claim to its anchor source.

  Extends ProvenanceChain with audit capabilities, broken chain
  detection, and batch traceability analysis.

  Milestone target: 90%+ claim-to-anchor traceability.
  """

  alias Palimpedia.Confidence.ProvenanceChain

  require Logger

  @type trace_result :: %{
          node_id: integer(),
          node_title: String.t(),
          grounded: boolean(),
          anchor_distance: non_neg_integer() | nil,
          anchor_sources: [anchor_info()],
          citation_loop: boolean(),
          provenance_path: [String.t()]
        }

  @type anchor_info :: %{
          id: integer(),
          title: String.t(),
          provenance: [String.t()]
        }

  @type audit_result :: %{
          total_nodes: non_neg_integer(),
          traceable_nodes: non_neg_integer(),
          traceability_rate: float(),
          broken_chains: [integer()],
          citation_loops: [integer()],
          passes_audit: boolean()
        }

  @doc """
  Traces provenance for a node, returning a rich result with
  anchor info and the full provenance path.
  """
  def trace_node(node_id, opts \\ []) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())

    with {:ok, node} <- graph_repo.get_node(node_id),
         {:ok, chain} <- ProvenanceChain.trace(node_id, graph_repo, opts) do
      anchor_infos =
        Enum.map(chain.anchor_sources, fn anchor ->
          %{id: anchor.id, title: anchor.title, provenance: anchor.provenance}
        end)

      provenance_path = build_provenance_path(node, chain)

      {:ok,
       %{
         node_id: node_id,
         node_title: node.title,
         grounded: chain.grounded,
         anchor_distance: chain.anchor_distance,
         anchor_sources: anchor_infos,
         citation_loop: chain.citation_loop,
         provenance_path: provenance_path
       }}
    end
  end

  @doc """
  Runs a full audit: checks traceability for all generated nodes.
  Returns traceability rate and lists broken chains.

  The milestone target is 90%+ traceability.
  """
  def audit(opts \\ []) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())
    limit = Keyword.get(opts, :limit, 500)

    case graph_repo.find_generated_nodes(limit: limit) do
      {:ok, nodes} ->
        results =
          Enum.map(nodes, fn node ->
            case ProvenanceChain.trace(node.id, graph_repo, opts) do
              {:ok, chain} -> {node.id, chain}
              {:error, _} -> {node.id, %{grounded: false, citation_loop: false}}
            end
          end)

        total = length(results)
        traceable = Enum.count(results, fn {_id, chain} -> chain.grounded end)

        broken_chains =
          results
          |> Enum.filter(fn {_id, chain} ->
            not chain.grounded and not Map.get(chain, :citation_loop, false)
          end)
          |> Enum.map(fn {id, _} -> id end)

        citation_loops =
          results
          |> Enum.filter(fn {_id, chain} -> Map.get(chain, :citation_loop, false) end)
          |> Enum.map(fn {id, _} -> id end)

        rate = if total > 0, do: traceable / total, else: 1.0

        {:ok,
         %{
           total_nodes: total,
           traceable_nodes: traceable,
           traceability_rate: Float.round(rate, 4),
           broken_chains: broken_chains,
           citation_loops: citation_loops,
           passes_audit: rate >= 0.9
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Detects broken provenance chains: nodes that should be grounded
  but have lost their anchor connection.
  """
  def find_broken_chains(opts \\ []) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())

    case graph_repo.find_generated_nodes(limit: 500) do
      {:ok, nodes} ->
        # Only check nodes that claim provenance but aren't grounded
        broken =
          nodes
          |> Enum.filter(fn node -> node.provenance != [] end)
          |> Enum.filter(fn node ->
            case ProvenanceChain.trace(node.id, graph_repo, opts) do
              {:ok, %{grounded: false}} -> true
              _ -> false
            end
          end)
          |> Enum.map(fn node ->
            %{
              node_id: node.id,
              node_title: node.title,
              claimed_provenance: node.provenance,
              confidence: node.confidence
            }
          end)

        {:ok, broken}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Private ---

  defp build_provenance_path(node, chain) do
    node_step =
      "#{node.title} (#{node.node_type}, confidence: #{Float.round(node.confidence, 3)})"

    distance_step =
      if chain.anchor_distance do
        "#{chain.anchor_distance} hop(s) to anchor"
      else
        "no anchor path"
      end

    anchor_steps =
      Enum.map(chain.anchor_sources, fn anchor ->
        sources = Enum.join(anchor.provenance, ", ")
        "#{anchor.title} [#{sources}]"
      end)

    [node_step, distance_step | anchor_steps]
  end

  defp graph_repository do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
