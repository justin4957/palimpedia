defmodule Palimpedia.Interaction.UserTrustTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Interaction.UserTrust

  setup do
    {:ok, pid} =
      GenServer.start_link(UserTrust, [], name: :"trust_#{:erlang.unique_integer([:positive])}")

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{pid: pid}
  end

  defp record(pid, user_id, tier) do
    GenServer.call(pid, {:record, user_id, tier})
  end

  describe "record_interaction/2" do
    test "creates a new user profile on first interaction", %{pid: pid} do
      {:ok, profile} = record(pid, "user_1", :node_request)

      assert profile.user_id == "user_1"
      assert profile.total_interactions == 1
      assert profile.tier_counts.node_request == 1
      assert profile.trust_score > 0.0
    end

    test "higher-tier interactions earn more trust", %{pid: pid} do
      {:ok, p1} = record(pid, "tier1_user", :node_request)
      {:ok, p2} = record(pid, "tier2_user", :edge_assertion)
      {:ok, p3} = record(pid, "tier3_user", :contradiction_flag)

      # All start at 0.5, but get different deltas
      assert p3.trust_score > p2.trust_score
      assert p2.trust_score > p1.trust_score
    end

    test "trust accumulates across interactions", %{pid: pid} do
      record(pid, "active_user", :edge_assertion)
      record(pid, "active_user", :edge_assertion)
      {:ok, profile} = record(pid, "active_user", :contradiction_flag)

      assert profile.total_interactions == 3
      assert profile.tier_counts.edge_assertion == 2
      assert profile.tier_counts.contradiction_flag == 1
      assert profile.trust_score > 0.5
    end
  end

  describe "approval and rejection" do
    test "approval boosts trust", %{pid: pid} do
      record(pid, "user_a", :node_request)
      {:ok, before} = GenServer.call(pid, {:get, "user_a"})

      {:ok, after_approval} = GenServer.call(pid, {:approval, "user_a"})
      assert after_approval.trust_score > before.trust_score
      assert after_approval.approved_contributions == 1
    end

    test "rejection reduces trust", %{pid: pid} do
      record(pid, "user_b", :edge_assertion)
      {:ok, before} = GenServer.call(pid, {:get, "user_b"})

      {:ok, after_rejection} = GenServer.call(pid, {:rejection, "user_b"})
      assert after_rejection.trust_score < before.trust_score
      assert after_rejection.rejected_contributions == 1
    end

    test "trust is clamped to 0.0-1.0", %{pid: pid} do
      record(pid, "user_c", :node_request)

      # Many rejections
      for _ <- 1..20 do
        GenServer.call(pid, {:rejection, "user_c"})
      end

      {:ok, profile} = GenServer.call(pid, {:get, "user_c"})
      assert profile.trust_score == 0.0
    end
  end

  describe "get_profile/1" do
    test "returns error for unknown user", %{pid: pid} do
      {:error, :not_found} = GenServer.call(pid, {:get, "nonexistent"})
    end
  end
end
