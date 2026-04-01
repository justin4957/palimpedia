defmodule Mix.Tasks.Palimpedia.Graph.Report do
  @moduledoc """
  Generates a validation report for the graph, verifying the seed corpus.

  ## Usage

      mix palimpedia.graph.report

  Outputs:
  - Node counts by type
  - Edge count
  - Confidence distribution
  - Anchor grounding verification
  - Nodes requiring regrounding
  - Orphan node count
  """

  use Mix.Task

  alias Palimpedia.Confidence.Scorer

  @shortdoc "Generate a graph statistics and validation report"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    graph_repo =
      Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)

    Mix.shell().info("=== Palimpedia Graph Report ===\n")

    report_stats(graph_repo)
    report_anchor_grounding(graph_repo)
    report_orphans(graph_repo)
    report_regrounding(graph_repo)

    Mix.shell().info("\n=== Report Complete ===")
  end

  defp report_stats(graph_repo) do
    case graph_repo.stats() do
      {:ok, stats} ->
        Mix.shell().info("Node Counts:")
        Mix.shell().info("  Total nodes:     #{stats.total_nodes}")
        Mix.shell().info("  Anchor nodes:    #{stats.anchor_nodes}")
        Mix.shell().info("  Generated nodes: #{stats.generated_nodes}")
        Mix.shell().info("  Requested nodes: #{stats.requested_nodes}")
        Mix.shell().info("  Bridge nodes:    #{stats.bridge_nodes}")
        Mix.shell().info("")
        Mix.shell().info("Edge Count: #{stats.total_edges}")
        Mix.shell().info("")

        avg =
          if stats.avg_confidence do
            Float.round(stats.avg_confidence, 4)
          else
            "N/A"
          end

        Mix.shell().info("Average Confidence: #{avg}")
        Mix.shell().info("")

        if stats.total_nodes >= 10_000 do
          Mix.shell().info("[PASS] Phase 0 milestone: 10,000+ nodes (#{stats.total_nodes})")
        else
          Mix.shell().info(
            "[PENDING] Phase 0 milestone: #{stats.total_nodes}/10,000 nodes (#{Float.round(stats.total_nodes / 10_000 * 100, 1)}%)"
          )
        end

        Mix.shell().info("")

      {:error, reason} ->
        Mix.shell().error("Failed to fetch stats: #{inspect(reason)}")
    end
  end

  defp report_anchor_grounding(graph_repo) do
    Mix.shell().info("Anchor Grounding Verification:")

    case graph_repo.search_nodes("", limit: 100) do
      {:ok, nodes} ->
        anchor_count = Enum.count(nodes, &(&1.node_type == :anchor))

        grounded_count =
          Enum.count(nodes, &(&1.anchor_distance != nil && &1.anchor_distance >= 0))

        full_confidence = Enum.count(nodes, &(&1.confidence == 1.0))

        Mix.shell().info("  Sample size: #{length(nodes)} nodes")
        Mix.shell().info("  Anchors: #{anchor_count}")
        Mix.shell().info("  Grounded (anchor_distance >= 0): #{grounded_count}")
        Mix.shell().info("  Full confidence (1.0): #{full_confidence}")
        Mix.shell().info("")

      {:error, _} ->
        Mix.shell().info("  (Could not sample nodes)")
        Mix.shell().info("")
    end
  end

  defp report_orphans(graph_repo) do
    case graph_repo.find_orphans(limit: 100) do
      {:ok, orphans} ->
        Mix.shell().info("Orphan Nodes (no edges): #{length(orphans)}")

        if length(orphans) > 0 do
          Enum.take(orphans, 5)
          |> Enum.each(fn node ->
            Mix.shell().info("  - #{node.title} (id=#{node.id}, type=#{node.node_type})")
          end)

          if length(orphans) > 5 do
            Mix.shell().info("  ... and #{length(orphans) - 5} more")
          end
        end

        Mix.shell().info("")

      {:error, _} ->
        Mix.shell().info("Orphan Nodes: (query failed)")
        Mix.shell().info("")
    end
  end

  defp report_regrounding(graph_repo) do
    max_hops = Scorer.max_anchor_hops()

    case graph_repo.find_ungrounded(max_hops, limit: 100) do
      {:ok, nodes} ->
        Mix.shell().info("Nodes Requiring Regrounding (distance > #{max_hops}): #{length(nodes)}")

        if length(nodes) > 0 do
          Enum.take(nodes, 5)
          |> Enum.each(fn node ->
            Mix.shell().info(
              "  - #{node.title} (distance=#{node.anchor_distance}, confidence=#{node.confidence})"
            )
          end)
        end

      {:error, _} ->
        Mix.shell().info("Regrounding check: (query failed)")
    end
  end
end
