defmodule Palimpedia.Confidence.Scorer do
  @moduledoc """
  Confidence scoring and decay system.

  Claims decay when contradicted. Contradictions trigger subgraph review.
  Confidence scores cannot propagate across more than N hops without
  anchor re-grounding (prevents citation loops).
  """

  @max_anchor_hops 3

  @doc """
  Calculates confidence for a node based on its provenance chain
  and distance from anchor sources.
  """
  def calculate(provenance_chain, anchor_distance) do
    base_confidence = provenance_confidence(provenance_chain)
    distance_decay = distance_penalty(anchor_distance)

    max(0.0, base_confidence * distance_decay)
  end

  @doc """
  Applies temporal decay to a confidence score.
  Scores degrade over time, requiring re-evaluation.
  """
  def apply_temporal_decay(confidence, generated_at) do
    days_elapsed = DateTime.diff(DateTime.utc_now(), generated_at, :day)
    decay_rate = 0.001
    decay_factor = :math.exp(-decay_rate * days_elapsed)

    confidence * decay_factor
  end

  @doc """
  Returns true if a node's confidence chain has exceeded the maximum
  allowed hops from an anchor source (citation loop risk).
  """
  def requires_regrounding?(anchor_distance) do
    anchor_distance != nil and anchor_distance > @max_anchor_hops
  end

  defp provenance_confidence([]), do: 0.0
  defp provenance_confidence(chain), do: min(1.0, length(chain) * 0.2)

  defp distance_penalty(nil), do: 0.1
  defp distance_penalty(0), do: 1.0

  defp distance_penalty(distance) when distance > 0 do
    1.0 / (1.0 + distance * 0.3)
  end
end
