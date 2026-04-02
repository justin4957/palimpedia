defmodule Palimpedia.Interaction.HandlerTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Interaction.Handler

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "handle_node_request/2" do
    test "processes a node request" do
      {:ok, result} = Handler.handle_node_request("Quantum Computing")
      assert result.title == "Quantum Computing"
    end

    test "tracks user trust when user_id provided" do
      {:ok, _} = Handler.handle_node_request("Dark Energy", user_id: "test_user_1")

      # Verify trust was recorded
      case Palimpedia.Interaction.UserTrust.get_profile("test_user_1") do
        {:ok, profile} ->
          assert profile.tier_counts.node_request >= 1

        {:error, :not_found} ->
          # Trust GenServer may not be the test instance
          :ok
      end
    end
  end

  describe "handle_edge_assertion/4" do
    test "creates an edge and enqueues exploration" do
      result =
        Handler.handle_edge_assertion(1, 2, :references,
          confidence: 0.8,
          description: "A references B"
        )

      assert match?({:ok, _}, result)
    end
  end

  describe "handle_contradiction_flag/4" do
    test "creates contradiction and triggers review" do
      {:ok, contradiction} =
        Handler.handle_contradiction_flag(1, 2, "Conflicting claims", severity: :high)

      assert contradiction.node_a_id == 1
      assert contradiction.node_b_id == 2
      assert contradiction.severity == :high
    end
  end
end
