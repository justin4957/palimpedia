defmodule Palimpedia.Interaction.UserInputTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Interaction.UserInput

  describe "node_request/2" do
    test "creates a tier 1 node request" do
      input = UserInput.node_request("Quantum Computing", user_id: "user_123")

      assert input.tier == :node_request
      assert input.payload.title == "Quantum Computing"
      assert input.user_id == "user_123"
      assert input.timestamp != nil
    end
  end

  describe "edge_assertion/4" do
    test "creates a tier 2 edge assertion" do
      input =
        UserInput.edge_assertion(
          "Bell Theorem",
          "EPR Paradox",
          "contradicts",
          description: "Bell's theorem disproves local hidden variables"
        )

      assert input.tier == :edge_assertion
      assert input.payload.source == "Bell Theorem"
      assert input.payload.target == "EPR Paradox"
      assert input.payload.relationship == "contradicts"
    end
  end

  describe "contradiction_flag/4" do
    test "creates a tier 3 contradiction flag" do
      input =
        UserInput.contradiction_flag(
          "node_abc",
          "node_def",
          "Conflicting dates for the same event"
        )

      assert input.tier == :contradiction_flag
      assert input.payload.node_a_id == "node_abc"
      assert input.payload.node_b_id == "node_def"
    end
  end
end
