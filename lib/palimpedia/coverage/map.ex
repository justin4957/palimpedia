defmodule Palimpedia.Coverage.Map do
  @moduledoc """
  Coverage map: graph density analysis, confidence distribution,
  blind spot reporting, and epistemic gap indexing.

  "The system's gaps and generation patterns are themselves data —
  an index of what knowledge structures the seed corpus encodes
  and what it systematically occludes."
  """

  alias Palimpedia.GapDetection.{Analyzer, Scheduler}

  require Logger

  @type coverage_report :: %{
          density: map(),
          confidence_distribution: map(),
          blind_spots: [blind_spot()],
          known_gaps: [map()],
          epistemic_index: epistemic_index(),
          generated_at: DateTime.t()
        }

  @type blind_spot :: %{
          domain: String.t(),
          node_count: non_neg_integer(),
          avg_degree: float(),
          anchor_ratio: float(),
          severity: :high | :medium | :low,
          description: String.t()
        }

  @type epistemic_index :: %{
          total_nodes: non_neg_integer(),
          total_gaps: non_neg_integer(),
          coverage_score: float(),
          underrepresented_domains: [String.t()],
          blind_spot_count: non_neg_integer(),
          summary: String.t()
        }

  @doc """
  Generates a full coverage report for the graph.
  """
  def generate_report(opts \\ []) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())

    density = compute_density(graph_repo)
    distribution = compute_confidence_distribution(graph_repo)
    blind_spots = detect_blind_spots(density)
    known_gaps = fetch_known_gaps(opts)
    epistemic = build_epistemic_index(density, blind_spots, known_gaps)

    {:ok,
     %{
       density: density,
       confidence_distribution: distribution,
       blind_spots: blind_spots,
       known_gaps: known_gaps,
       epistemic_index: epistemic,
       generated_at: DateTime.utc_now()
     }}
  end

  @doc "Returns graph density statistics by node type."
  def compute_density(graph_repo) do
    case graph_repo.coverage_by_type() do
      {:ok, coverage} ->
        total_nodes =
          coverage |> Map.values() |> Enum.map(& &1.node_count) |> Enum.sum()

        total_edges =
          coverage |> Map.values() |> Enum.map(& &1.edge_count) |> Enum.sum()

        anchor_count = get_in(coverage, ["anchor", :node_count]) || 0
        generated_count = get_in(coverage, ["generated", :node_count]) || 0

        generation_ratio =
          if anchor_count > 0, do: generated_count / anchor_count, else: 0.0

        %{
          by_type: coverage,
          total_nodes: total_nodes,
          total_edges: total_edges,
          anchor_count: anchor_count,
          generated_count: generated_count,
          generation_to_anchor_ratio: Float.round(generation_ratio, 3),
          overall_density:
            if(total_nodes > 0, do: Float.round(total_edges / total_nodes, 3), else: 0.0)
        }

      {:error, _} ->
        %{
          by_type: %{},
          total_nodes: 0,
          total_edges: 0,
          anchor_count: 0,
          generated_count: 0,
          generation_to_anchor_ratio: 0.0,
          overall_density: 0.0
        }
    end
  end

  @doc "Computes a histogram of confidence scores across the graph."
  def compute_confidence_distribution(graph_repo) do
    case graph_repo.find_generated_nodes(limit: 1000) do
      {:ok, nodes} ->
        buckets = %{
          "0.0-0.2" => 0,
          "0.2-0.4" => 0,
          "0.4-0.6" => 0,
          "0.6-0.8" => 0,
          "0.8-1.0" => 0
        }

        distribution =
          Enum.reduce(nodes, buckets, fn node, acc ->
            bucket = confidence_bucket(node.confidence)
            Map.update(acc, bucket, 1, &(&1 + 1))
          end)

        total = length(nodes)

        avg =
          if total > 0,
            do: nodes |> Enum.map(& &1.confidence) |> Enum.sum() |> Kernel./(total),
            else: 0.0

        %{
          histogram: distribution,
          total_nodes: total,
          avg_confidence: Float.round(avg, 4),
          median_confidence: compute_median(nodes)
        }

      {:error, _} ->
        %{histogram: %{}, total_nodes: 0, avg_confidence: 0.0, median_confidence: 0.0}
    end
  end

  @doc """
  Detects blind spots: domains with low anchor coverage or
  disproportionately high generation-to-anchor ratio.
  """
  def detect_blind_spots(density) do
    by_type = density.by_type
    overall_density = density.overall_density

    by_type
    |> Enum.filter(fn {_type, stats} -> stats.node_count > 0 end)
    |> Enum.map(fn {domain, stats} ->
      severity = classify_blind_spot_severity(stats, overall_density)

      %{
        domain: domain,
        node_count: stats.node_count,
        avg_degree: Float.round(stats.avg_degree, 2),
        anchor_ratio: 0.0,
        severity: severity,
        description: blind_spot_description(domain, stats, severity)
      }
    end)
    |> Enum.filter(&(&1.severity != :none))
    |> Enum.sort_by(fn bs -> severity_rank(bs.severity) end, :desc)
  end

  @doc "Returns the cached known gaps from the Scheduler, or runs fresh analysis."
  def fetch_known_gaps(opts \\ []) do
    cached = Scheduler.latest_result()

    gaps =
      if cached do
        cached.gaps
      else
        case Analyzer.analyze(opts) do
          {:ok, result} -> result.gaps
        end
      end

    gaps
    |> Enum.take(Keyword.get(opts, :limit, 50))
    |> Enum.map(fn gap ->
      %{
        gap_type: gap.gap_type,
        priority: Float.round(gap.priority, 2),
        suggested_title: gap.suggested_title,
        context: gap.context
      }
    end)
  end

  # --- Private ---

  defp build_epistemic_index(density, blind_spots, known_gaps) do
    total_nodes = density.total_nodes
    total_gaps = length(known_gaps)
    blind_spot_count = length(blind_spots)

    coverage_score =
      if total_nodes > 0 do
        gap_penalty = min(1.0, total_gaps * 0.01)
        spot_penalty = min(0.5, blind_spot_count * 0.1)
        max(0.0, 1.0 - gap_penalty - spot_penalty)
      else
        0.0
      end

    underrepresented =
      blind_spots
      |> Enum.filter(&(&1.severity in [:high, :medium]))
      |> Enum.map(& &1.domain)

    summary = build_summary(total_nodes, total_gaps, blind_spot_count, coverage_score)

    %{
      total_nodes: total_nodes,
      total_gaps: total_gaps,
      coverage_score: Float.round(coverage_score, 3),
      underrepresented_domains: underrepresented,
      blind_spot_count: blind_spot_count,
      summary: summary
    }
  end

  defp build_summary(total_nodes, total_gaps, blind_spots, coverage_score) do
    score_label =
      cond do
        coverage_score >= 0.8 -> "strong"
        coverage_score >= 0.5 -> "moderate"
        coverage_score >= 0.2 -> "weak"
        true -> "minimal"
      end

    "Graph contains #{total_nodes} nodes with #{score_label} coverage " <>
      "(score: #{Float.round(coverage_score, 2)}). " <>
      "#{total_gaps} structural gaps detected. " <>
      "#{blind_spots} blind spots identified."
  end

  defp confidence_bucket(c) when c < 0.2, do: "0.0-0.2"
  defp confidence_bucket(c) when c < 0.4, do: "0.2-0.4"
  defp confidence_bucket(c) when c < 0.6, do: "0.4-0.6"
  defp confidence_bucket(c) when c < 0.8, do: "0.6-0.8"
  defp confidence_bucket(_), do: "0.8-1.0"

  defp compute_median([]), do: 0.0

  defp compute_median(nodes) do
    sorted = nodes |> Enum.map(& &1.confidence) |> Enum.sort()
    mid = div(length(sorted), 2)

    if rem(length(sorted), 2) == 0 do
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    else
      Enum.at(sorted, mid)
    end
  end

  defp classify_blind_spot_severity(stats, overall_density) do
    cond do
      stats.avg_degree == 0.0 -> :high
      overall_density > 0 and stats.avg_degree < overall_density * 0.3 -> :high
      overall_density > 0 and stats.avg_degree < overall_density * 0.6 -> :medium
      stats.node_count < 3 -> :low
      true -> :none
    end
  end

  defp blind_spot_description(domain, stats, :high) do
    "#{domain}: severely underconnected (avg degree #{Float.round(stats.avg_degree, 1)}, #{stats.node_count} nodes)"
  end

  defp blind_spot_description(domain, stats, :medium) do
    "#{domain}: below-average connectivity (avg degree #{Float.round(stats.avg_degree, 1)})"
  end

  defp blind_spot_description(domain, stats, _) do
    "#{domain}: low node count (#{stats.node_count} nodes)"
  end

  defp severity_rank(:high), do: 3
  defp severity_rank(:medium), do: 2
  defp severity_rank(:low), do: 1
  defp severity_rank(_), do: 0

  defp graph_repository do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
