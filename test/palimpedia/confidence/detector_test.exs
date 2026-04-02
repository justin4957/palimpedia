defmodule Palimpedia.Confidence.DetectorTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Confidence.{Detector, Contradiction, Scorer}
  alias Palimpedia.Graph.Node

  setup do
    # The global Contradiction store is started by the application supervisor.
    # We just need to ensure it's clean for each test by listing and checking state.
    # Since we can't easily reset ETS from outside, we rely on unique node IDs per test.
    :ok
  end

  describe "check_pair/2" do
    test "detects negation-pattern contradictions" do
      node_a = %Node{
        id: 1,
        title: "Bell's Theorem",
        content:
          "Bell's theorem proves that local hidden variables are incompatible with quantum mechanics.",
        node_type: :anchor,
        confidence: 1.0
      }

      node_b = %Node{
        id: 2,
        title: "EPR Argument",
        content:
          "The EPR argument suggests local hidden variables are compatible with quantum mechanics.",
        node_type: :anchor,
        confidence: 1.0
      }

      {:ok, contradictions} = Detector.check_pair(node_a, node_b)
      assert length(contradictions) > 0

      [c | _] = contradictions
      assert c.status == :open
      assert c.flagged_by == :system
      assert String.contains?(c.description, "contradiction")
    end

    test "detects conflicting dates" do
      node_a = %Node{
        id: 1,
        title: "Event A",
        content: "The quantum theory was formalized in 1925 by Heisenberg.",
        node_type: :anchor,
        confidence: 1.0
      }

      node_b = %Node{
        id: 2,
        title: "Event B",
        content: "The quantum theory was formalized in 1926 by Schrödinger.",
        node_type: :anchor,
        confidence: 1.0
      }

      {:ok, contradictions} = Detector.check_pair(node_a, node_b)
      assert length(contradictions) > 0
    end

    test "returns empty for non-contradicting content" do
      node_a = %Node{
        id: 1,
        title: "Physics",
        content: "Physics studies the behavior of matter and energy.",
        node_type: :anchor,
        confidence: 1.0
      }

      node_b = %Node{
        id: 2,
        title: "Chemistry",
        content: "Chemistry studies the composition of substances.",
        node_type: :anchor,
        confidence: 1.0
      }

      {:ok, contradictions} = Detector.check_pair(node_a, node_b)
      assert contradictions == []
    end

    test "handles empty content gracefully" do
      node_a = %Node{id: 1, title: "A", content: nil, node_type: :anchor, confidence: 1.0}

      node_b = %Node{
        id: 2,
        title: "B",
        content: "Some content",
        node_type: :anchor,
        confidence: 1.0
      }

      {:ok, contradictions} = Detector.check_pair(node_a, node_b)
      assert contradictions == []
    end
  end

  describe "apply_penalties/2" do
    test "reduces confidence by contradiction count" do
      # Use unique IDs to avoid interference from other tests
      unique_id = :erlang.unique_integer([:positive]) + 100_000
      Contradiction.flag(unique_id, unique_id + 1, "First conflict")
      Contradiction.flag(unique_id, unique_id + 2, "Second conflict")

      penalized = Detector.apply_penalties(unique_id, 1.0)
      expected = Scorer.apply_contradiction_penalty(1.0, 2)
      assert penalized == expected
      assert penalized < 1.0
    end

    test "zero contradictions leaves confidence unchanged" do
      unique_id = :erlang.unique_integer([:positive]) + 200_000
      penalized = Detector.apply_penalties(unique_id, 0.8)
      assert penalized == 0.8
    end
  end
end
