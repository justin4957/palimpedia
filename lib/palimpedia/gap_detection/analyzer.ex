defmodule Palimpedia.GapDetection.Analyzer do
  @moduledoc """
  Layer 2: Continuous graph analytics for structural gap detection.

  Identifies structural holes, orphaned concepts, asymmetric coverage,
  and temporal gaps. Produces a priority-ordered generation queue.
  """

  @type gap :: %{
          gap_type: gap_type(),
          region: [String.t()],
          pressure: float(),
          suggested_title: String.t() | nil,
          context_node_ids: [String.t()]
        }

  @type gap_type :: :structural_hole | :orphan | :asymmetric_coverage | :temporal_gap

  @doc """
  Scans the graph for structural gaps and returns them priority-ordered.
  Higher pressure = more urgently needed bridge document.
  """
  @callback detect_gaps(keyword()) :: {:ok, [gap()]} | {:error, term()}

  @doc """
  Calculates relational pressure for a specific region of the graph.
  Combines edge density, user demand signals, and confidence delta.
  """
  @callback calculate_pressure(region_node_ids :: [String.t()]) ::
              {:ok, float()} | {:error, term()}
end
