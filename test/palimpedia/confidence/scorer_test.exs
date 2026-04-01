defmodule Palimpedia.Confidence.ScorerTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Confidence.Scorer
  alias Palimpedia.Graph.Node

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

    test "more provenance sources increase confidence" do
      one_source = Scorer.calculate(["a"], 0)
      three_sources = Scorer.calculate(["a", "b", "c"], 0)

      assert three_sources > one_source
    end

    test "confidence caps at 1.0 regardless of provenance count" do
      many_sources = Enum.map(1..20, &"source_#{&1}")
      score = Scorer.calculate(many_sources, 0)

      assert score == 1.0
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

    test "decay is monotonic — older is always lower" do
      base = 0.8
      t30 = DateTime.utc_now() |> DateTime.add(-30, :day)
      t90 = DateTime.utc_now() |> DateTime.add(-90, :day)
      t365 = DateTime.utc_now() |> DateTime.add(-365, :day)

      assert Scorer.apply_temporal_decay(base, t30) > Scorer.apply_temporal_decay(base, t90)
      assert Scorer.apply_temporal_decay(base, t90) > Scorer.apply_temporal_decay(base, t365)
    end
  end

  describe "apply_contradiction_penalty/2" do
    test "each contradiction reduces confidence" do
      assert Scorer.apply_contradiction_penalty(1.0, 1) == 1.0 - Scorer.contradiction_penalty()
    end

    test "multiple contradictions stack" do
      result = Scorer.apply_contradiction_penalty(1.0, 2)
      assert result == 1.0 - 2 * Scorer.contradiction_penalty()
    end

    test "confidence floors at 0.0" do
      assert Scorer.apply_contradiction_penalty(0.1, 10) == 0.0
    end

    test "zero contradictions has no effect" do
      assert Scorer.apply_contradiction_penalty(0.8, 0) == 0.8
    end
  end

  describe "propagation_effects/2" do
    test "anchor node propagates to ungrounded neighbor" do
      anchor = %Node{
        id: 1,
        title: "Anchor",
        node_type: :anchor,
        confidence: 1.0,
        anchor_distance: 0,
        provenance: ["wikidata:Q1"]
      }

      ungrounded = %Node{
        id: 2,
        title: "Ungrounded",
        node_type: :generated,
        confidence: 0.0,
        anchor_distance: nil,
        provenance: []
      }

      updates = Scorer.propagation_effects(anchor, ungrounded)
      assert length(updates) == 1

      [{node_id, new_confidence, new_distance}] = updates
      assert node_id == 2
      assert new_distance == 1
      assert new_confidence > 0.0
    end

    test "does not propagate when source has no anchor path" do
      ungrounded_a = %Node{
        id: 1,
        title: "A",
        node_type: :generated,
        confidence: 0.0,
        anchor_distance: nil,
        provenance: []
      }

      ungrounded_b = %Node{
        id: 2,
        title: "B",
        node_type: :generated,
        confidence: 0.0,
        anchor_distance: nil,
        provenance: []
      }

      assert Scorer.propagation_effects(ungrounded_a, ungrounded_b) == []
    end

    test "propagates to closer path when beneficial" do
      closer = %Node{
        id: 1,
        title: "Close",
        node_type: :generated,
        confidence: 0.5,
        anchor_distance: 1,
        provenance: ["src:a"]
      }

      farther = %Node{
        id: 2,
        title: "Far",
        node_type: :generated,
        confidence: 0.1,
        anchor_distance: 5,
        provenance: ["src:b"]
      }

      updates = Scorer.propagation_effects(closer, farther)
      assert length(updates) == 1

      [{node_id, _conf, new_distance}] = updates
      assert node_id == 2
      assert new_distance == 2
    end

    test "does not propagate beyond max anchor hops" do
      at_limit = %Node{
        id: 1,
        title: "At Limit",
        node_type: :generated,
        confidence: 0.3,
        anchor_distance: Scorer.max_anchor_hops(),
        provenance: ["src:a"]
      }

      ungrounded = %Node{
        id: 2,
        title: "Beyond",
        node_type: :generated,
        confidence: 0.0,
        anchor_distance: nil,
        provenance: []
      }

      # distance would be max_hops + 1 which exceeds limit
      assert Scorer.propagation_effects(at_limit, ungrounded) == []
    end
  end

  describe "max_anchor_hops/0" do
    test "returns the configured maximum" do
      assert Scorer.max_anchor_hops() == 3
    end
  end
end
