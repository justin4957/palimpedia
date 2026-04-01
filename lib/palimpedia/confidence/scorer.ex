defmodule Palimpedia.Confidence.Scorer do
  @moduledoc """
  Confidence scoring and decay system.

  Claims decay when contradicted. Contradictions trigger subgraph review.
  Confidence scores cannot propagate across more than N hops without
  anchor re-grounding (prevents citation loops).

  ## Scoring Model

  A node's confidence is the product of three factors:

      confidence = provenance_confidence × distance_penalty × temporal_decay

  - **Provenance confidence**: based on the number of distinct anchor sources
    in the node's provenance chain (more sources = higher confidence, capped at 1.0).
  - **Distance penalty**: decays as anchor distance increases. Nodes with no
    anchor path get a heavy penalty (0.1).
  - **Temporal decay**: exponential decay based on age since generation.

  ## Propagation Rules

  When a new edge is created between nodes A and B:
  - If A is an anchor and B is not, B's anchor_distance may decrease
  - If B gains a shorter anchor path, its confidence increases
  - Contradicting edges penalize both endpoints

  Confidence never propagates beyond `@max_anchor_hops` without re-grounding.
  """

  alias Palimpedia.Confidence.ProvenanceChain
  alias Palimpedia.Graph.Node

  @max_anchor_hops 3
  @temporal_decay_rate 0.001
  @contradiction_penalty 0.3

  @doc """
  Calculates confidence for a node based on its provenance chain
  and distance from anchor sources.
  """
  def calculate(provenance_chain, anchor_distance) do
    base_confidence = provenance_confidence(provenance_chain)
    decay = distance_penalty(anchor_distance)

    max(0.0, base_confidence * decay)
  end

  @doc """
  Scores a node using live graph data — traces provenance, computes distance,
  and returns the updated confidence score.

  Returns `{:ok, score, chain_result}` with the new confidence and the
  provenance chain data used to compute it.
  """
  def score_node(%Node{} = node, graph_repo, opts \\ []) do
    case ProvenanceChain.trace(node.id, graph_repo, opts) do
      {:ok, chain} ->
        provenance = Enum.map(chain.anchor_sources, fn a -> hd(a.provenance) end)
        base_score = calculate(provenance, chain.anchor_distance)

        final_score =
          case node.generated_at do
            nil -> base_score
            generated_at -> apply_temporal_decay(base_score, generated_at)
          end

        {:ok, final_score, chain}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Computes confidence propagation effect when a new edge is created.

  Returns a list of `{node_id, new_confidence, new_anchor_distance}` tuples
  for nodes whose confidence should be updated.
  """
  def propagation_effects(source_node, target_node) do
    updates = []

    # If source is closer to an anchor, target may benefit
    updates =
      if should_propagate?(source_node, target_node) do
        new_distance = (source_node.anchor_distance || 0) + 1
        new_confidence = calculate(source_node.provenance, new_distance)
        [{target_node.id, new_confidence, new_distance} | updates]
      else
        updates
      end

    # Symmetric: if target is closer, source may benefit
    updates =
      if should_propagate?(target_node, source_node) do
        new_distance = (target_node.anchor_distance || 0) + 1
        new_confidence = calculate(target_node.provenance, new_distance)
        [{source_node.id, new_confidence, new_distance} | updates]
      else
        updates
      end

    updates
  end

  @doc """
  Applies a contradiction penalty to a confidence score.
  Each active contradiction reduces confidence by `@contradiction_penalty`.
  """
  def apply_contradiction_penalty(confidence, active_contradiction_count) do
    penalty = active_contradiction_count * @contradiction_penalty
    max(0.0, confidence - penalty)
  end

  @doc """
  Applies temporal decay to a confidence score.
  Scores degrade over time, requiring re-evaluation.
  """
  def apply_temporal_decay(confidence, generated_at) do
    days_elapsed = DateTime.diff(DateTime.utc_now(), generated_at, :day)
    decay_factor = :math.exp(-@temporal_decay_rate * days_elapsed)

    confidence * decay_factor
  end

  @doc """
  Returns true if a node's confidence chain has exceeded the maximum
  allowed hops from an anchor source (citation loop risk).
  """
  def requires_regrounding?(anchor_distance) do
    anchor_distance != nil and anchor_distance > @max_anchor_hops
  end

  @doc "Maximum allowed hops from an anchor before regrounding is required."
  def max_anchor_hops, do: @max_anchor_hops

  @doc "The per-contradiction confidence penalty."
  def contradiction_penalty, do: @contradiction_penalty

  # --- Private ---

  defp provenance_confidence([]), do: 0.0
  defp provenance_confidence(chain), do: min(1.0, length(chain) * 0.2)

  defp distance_penalty(nil), do: 0.1
  defp distance_penalty(0), do: 1.0

  defp distance_penalty(distance) when distance > 0 do
    1.0 / (1.0 + distance * 0.3)
  end

  defp should_propagate?(closer_node, farther_node) do
    closer_distance = closer_node.anchor_distance
    farther_distance = farther_node.anchor_distance

    cond do
      # Closer node has no anchor path — can't propagate
      is_nil(closer_distance) -> false
      # Farther node has no anchor path — any path helps
      is_nil(farther_distance) -> closer_distance + 1 <= @max_anchor_hops
      # Closer node offers a shorter path
      closer_distance + 1 < farther_distance -> true
      true -> false
    end
  end
end
