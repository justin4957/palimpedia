defmodule Palimpedia.GapDetection.Analyzer do
  @moduledoc """
  Layer 2: Graph analytics engine for structural gap detection.

  Identifies structural holes, orphaned concepts, asymmetric coverage,
  and low-connectivity nodes. Returns a priority-ordered list of gaps
  that feed the generation queue.

  ## Gap Types

  - `:structural_hole` — Two dense regions reachable via intermediate nodes
    but lacking a direct edge. High priority: bridge documents needed.
  - `:orphan` — Nodes with zero connections. Medium priority.
  - `:low_connectivity` — Nodes with very few edges relative to their type.
  - `:asymmetric_coverage` — Node types with disproportionately low edge density.
  """

  require Logger

  @type gap :: %{
          gap_type: gap_type(),
          priority: float(),
          suggested_title: String.t() | nil,
          context: map()
        }

  @type gap_type :: :structural_hole | :orphan | :low_connectivity | :asymmetric_coverage

  @type analysis_result :: %{
          gaps: [gap()],
          stats: map(),
          analyzed_at: DateTime.t()
        }

  @doc """
  Runs a full gap analysis across the graph.
  Returns gaps priority-ordered (highest first).

  ## Options
    * `:graph_repo` - Graph repository module
    * `:min_edges` - Threshold for low-connectivity detection (default: 2)
    * `:structural_hole_hops` - Max hops for structural hole search (default: 3)
    * `:limit` - Max gaps per type (default: 50)
  """
  def analyze(opts \\ []) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())
    min_edges = Keyword.get(opts, :min_edges, 2)
    hole_hops = Keyword.get(opts, :structural_hole_hops, 3)
    limit = Keyword.get(opts, :limit, 50)

    Logger.info("Starting gap analysis...")

    orphan_gaps = detect_orphans(graph_repo, limit)
    low_conn_gaps = detect_low_connectivity(graph_repo, min_edges, limit)
    structural_gaps = detect_structural_holes(graph_repo, hole_hops, limit)
    coverage_gaps = detect_asymmetric_coverage(graph_repo)

    all_gaps =
      (orphan_gaps ++ low_conn_gaps ++ structural_gaps ++ coverage_gaps)
      |> Enum.sort_by(& &1.priority, :desc)

    stats = %{
      orphans: length(orphan_gaps),
      low_connectivity: length(low_conn_gaps),
      structural_holes: length(structural_gaps),
      asymmetric_coverage: length(coverage_gaps),
      total_gaps: length(all_gaps)
    }

    Logger.info("Gap analysis complete: #{stats.total_gaps} gaps found")

    {:ok,
     %{
       gaps: all_gaps,
       stats: stats,
       analyzed_at: DateTime.utc_now()
     }}
  end

  @doc """
  Detects orphan nodes (zero connections).
  """
  def detect_orphans(graph_repo, limit \\ 50) do
    case graph_repo.find_orphans(limit: limit) do
      {:ok, orphans} ->
        Enum.map(orphans, fn node ->
          %{
            gap_type: :orphan,
            priority: orphan_priority(node),
            suggested_title: nil,
            context: %{
              node_id: node.id,
              node_title: node.title,
              node_type: node.node_type
            }
          }
        end)

      {:error, reason} ->
        Logger.error("Orphan detection failed: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Detects nodes with fewer than `min_edges` connections.
  """
  def detect_low_connectivity(graph_repo, min_edges \\ 2, limit \\ 50) do
    case graph_repo.find_low_connectivity(min_edges, limit: limit) do
      {:ok, results} ->
        # Exclude true orphans (handled separately)
        results
        |> Enum.filter(fn %{degree: degree} -> degree > 0 end)
        |> Enum.map(fn %{node: node, degree: degree} ->
          %{
            gap_type: :low_connectivity,
            priority: low_connectivity_priority(node, degree),
            suggested_title: nil,
            context: %{
              node_id: node.id,
              node_title: node.title,
              degree: degree
            }
          }
        end)

      {:error, reason} ->
        Logger.error("Low connectivity detection failed: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Detects structural holes — pairs of nodes reachable via intermediate
  paths but lacking a direct edge. These are prime candidates for
  bridge document generation.
  """
  def detect_structural_holes(graph_repo, max_hops \\ 3, limit \\ 50) do
    case graph_repo.find_structural_holes(max_hops, limit: limit) do
      {:ok, holes} ->
        Enum.map(holes, fn %{node_a: node_a, node_b: node_b, indirect_paths: paths} ->
          suggested = "#{node_a.title} and #{node_b.title}"

          %{
            gap_type: :structural_hole,
            priority: structural_hole_priority(node_a, node_b, paths),
            suggested_title: suggested,
            context: %{
              node_a_id: node_a.id,
              node_a_title: node_a.title,
              node_b_id: node_b.id,
              node_b_title: node_b.title,
              indirect_paths: paths
            }
          }
        end)

      {:error, reason} ->
        Logger.error("Structural hole detection failed: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Detects node types with disproportionately low edge density compared
  to the overall average.
  """
  def detect_asymmetric_coverage(graph_repo) do
    case graph_repo.coverage_by_type() do
      {:ok, coverage} ->
        avg_degrees = coverage |> Map.values() |> Enum.map(& &1.avg_degree)

        overall_avg =
          if avg_degrees == [] do
            0.0
          else
            Enum.sum(avg_degrees) / length(avg_degrees)
          end

        coverage
        |> Enum.filter(fn {_type, stats} ->
          stats.node_count > 0 and stats.avg_degree < overall_avg * 0.5
        end)
        |> Enum.map(fn {node_type, stats} ->
          %{
            gap_type: :asymmetric_coverage,
            priority: coverage_priority(stats, overall_avg),
            suggested_title: nil,
            context: %{
              node_type: node_type,
              node_count: stats.node_count,
              avg_degree: stats.avg_degree,
              overall_avg_degree: overall_avg
            }
          }
        end)

      {:error, reason} ->
        Logger.error("Coverage analysis failed: #{inspect(reason)}")
        []
    end
  end

  # --- Priority scoring ---

  # Orphans with higher confidence are more urgent (they had value but lost connectivity)
  defp orphan_priority(node) do
    base = 5.0
    confidence_boost = node.confidence * 2.0
    # Anchor orphans are higher priority than generated orphans
    type_boost = if node.node_type == :anchor, do: 3.0, else: 0.0
    base + confidence_boost + type_boost
  end

  # Low connectivity is less urgent, but anchor nodes with few edges matter more
  defp low_connectivity_priority(node, degree) do
    base = 3.0
    # Fewer edges = higher priority
    edge_penalty = max(0.0, 2.0 - degree)
    type_boost = if node.node_type == :anchor, do: 2.0, else: 0.0
    base + edge_penalty + type_boost
  end

  # More indirect paths = stronger signal that a bridge is needed
  defp structural_hole_priority(node_a, node_b, indirect_paths) do
    base = 8.0
    path_boost = min(5.0, indirect_paths * 0.5)
    # Higher-confidence endpoints make the gap more significant
    confidence_boost = (node_a.confidence + node_b.confidence) * 1.5
    base + path_boost + confidence_boost
  end

  # Larger gap between type's density and average = higher priority
  defp coverage_priority(stats, overall_avg) do
    base = 2.0
    density_gap = max(0.0, overall_avg - stats.avg_degree)
    scale = min(3.0, stats.node_count * 0.1)
    base + density_gap * scale
  end

  defp graph_repository do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
