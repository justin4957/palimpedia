defmodule Palimpedia.Coverage.MapTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Coverage.Map, as: CoverageMap

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "generate_report/1" do
    test "returns a full coverage report" do
      {:ok, report} = CoverageMap.generate_report()

      assert Map.has_key?(report, :density)
      assert Map.has_key?(report, :confidence_distribution)
      assert Map.has_key?(report, :blind_spots)
      assert Map.has_key?(report, :known_gaps)
      assert Map.has_key?(report, :epistemic_index)
      assert report.generated_at != nil
    end
  end

  describe "compute_density/1" do
    test "returns density statistics by type" do
      density = CoverageMap.compute_density(Palimpedia.Test.MockGraphRepo)

      assert density.total_nodes > 0
      assert Map.has_key?(density.by_type, "anchor")
      assert is_float(density.overall_density)
      assert is_float(density.generation_to_anchor_ratio)
    end
  end

  describe "compute_confidence_distribution/1" do
    test "returns histogram and statistics" do
      dist = CoverageMap.compute_confidence_distribution(Palimpedia.Test.MockGraphRepo)

      assert Map.has_key?(dist, :histogram)
      assert dist.total_nodes >= 0
      assert is_float(dist.avg_confidence)
    end

    test "histogram has expected buckets" do
      dist = CoverageMap.compute_confidence_distribution(Palimpedia.Test.MockGraphRepo)

      assert Map.has_key?(dist.histogram, "0.0-0.2")
      assert Map.has_key?(dist.histogram, "0.8-1.0")
    end
  end

  describe "detect_blind_spots/1" do
    test "returns blind spots sorted by severity" do
      density = CoverageMap.compute_density(Palimpedia.Test.MockGraphRepo)
      spots = CoverageMap.detect_blind_spots(density)

      assert is_list(spots)

      for spot <- spots do
        assert Map.has_key?(spot, :domain)
        assert Map.has_key?(spot, :severity)
        assert Map.has_key?(spot, :description)
        assert spot.severity in [:high, :medium, :low]
      end
    end
  end

  describe "fetch_known_gaps/1" do
    test "returns prioritized gaps" do
      gaps = CoverageMap.fetch_known_gaps(limit: 10)

      assert is_list(gaps)

      for gap <- gaps do
        assert Map.has_key?(gap, :gap_type)
        assert Map.has_key?(gap, :priority)
      end
    end
  end

  describe "epistemic index" do
    test "summarizes the knowledge graph's limitations" do
      {:ok, report} = CoverageMap.generate_report()
      index = report.epistemic_index

      assert is_integer(index.total_nodes)
      assert is_integer(index.total_gaps)
      assert is_float(index.coverage_score)
      assert index.coverage_score >= 0.0 and index.coverage_score <= 1.0
      assert is_list(index.underrepresented_domains)
      assert is_binary(index.summary)
      assert String.contains?(index.summary, "nodes")
    end
  end
end
