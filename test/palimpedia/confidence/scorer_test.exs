defmodule Palimpedia.Confidence.ScorerTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Confidence.Scorer

  describe "calculate/2" do
    test "anchor nodes (distance 0) get full provenance confidence" do
      score = Scorer.calculate(["source_a", "source_b"], 0)

      assert score > 0.0
      assert score <= 1.0
    end

    test "empty provenance yields zero confidence" do
      assert Scorer.calculate([], 0) == 0.0
    end

    test "higher anchor distance reduces confidence" do
      near_score = Scorer.calculate(["source_a"], 1)
      far_score = Scorer.calculate(["source_a"], 5)

      assert near_score > far_score
    end

    test "nil anchor distance gets heavy penalty" do
      grounded_score = Scorer.calculate(["source_a"], 1)
      ungrounded_score = Scorer.calculate(["source_a"], nil)

      assert grounded_score > ungrounded_score
    end
  end

  describe "requires_regrounding?/1" do
    test "returns true when beyond max anchor hops" do
      assert Scorer.requires_regrounding?(4) == true
      assert Scorer.requires_regrounding?(10) == true
    end

    test "returns false within allowed hops" do
      assert Scorer.requires_regrounding?(0) == false
      assert Scorer.requires_regrounding?(3) == false
    end

    test "returns false for nil (unknown distance)" do
      assert Scorer.requires_regrounding?(nil) == false
    end
  end

  describe "apply_temporal_decay/2" do
    test "recent documents retain most confidence" do
      recent = DateTime.utc_now() |> DateTime.add(-1, :day)
      decayed = Scorer.apply_temporal_decay(1.0, recent)

      assert decayed > 0.99
    end

    test "old documents lose confidence" do
      old = DateTime.utc_now() |> DateTime.add(-365, :day)
      decayed = Scorer.apply_temporal_decay(1.0, old)

      assert decayed < 0.7
    end
  end
end
