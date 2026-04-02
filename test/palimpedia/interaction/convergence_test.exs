defmodule Palimpedia.Interaction.ConvergenceTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Interaction.Convergence

  setup do
    {:ok, pid} =
      GenServer.start_link(Convergence, [],
        name: :"convergence_#{:erlang.unique_integer([:positive])}"
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{pid: pid}
  end

  defp record(pid, topic, tier, user_id) do
    GenServer.call(pid, {:record, topic, tier, [user_id: user_id]})
  end

  describe "record_signal/3" do
    test "records a signal and returns :recorded", %{pid: pid} do
      assert {:ok, :recorded} = record(pid, "Quantum Computing", :node_request, "alice")
    end

    test "reaches convergence after threshold distinct users", %{pid: pid} do
      record(pid, "Dark Matter", :node_request, "alice")
      record(pid, "Dark Matter", :node_request, "bob")
      result = record(pid, "Dark Matter", :node_request, "charlie")

      assert {:ok, :converged, cluster} = result
      assert cluster.distinct_users == 3
      assert cluster.total_signals == 3
      assert cluster.converged == true
    end

    test "same user twice does not count as independent", %{pid: pid} do
      record(pid, "Dark Matter", :node_request, "alice")
      record(pid, "Dark Matter", :node_request, "alice")
      result = record(pid, "Dark Matter", :node_request, "alice")

      assert {:ok, :recorded} = result
    end

    test "returns :already_converged for subsequent signals", %{pid: pid} do
      record(pid, "Topic X", :node_request, "a")
      record(pid, "Topic X", :node_request, "b")
      record(pid, "Topic X", :node_request, "c")

      result = record(pid, "Topic X", :node_request, "d")
      assert {:ok, :already_converged, _} = result
    end

    test "normalizes topics (case-insensitive, trimmed)", %{pid: pid} do
      record(pid, "Quantum Mechanics", :node_request, "alice")
      record(pid, "quantum mechanics", :node_request, "bob")
      record(pid, "  QUANTUM MECHANICS  ", :node_request, "charlie")

      {:ok, cluster} = GenServer.call(pid, {:get, "quantum mechanics"})
      assert cluster.distinct_users == 3
      assert cluster.converged == true
    end

    test "different topics stay separate", %{pid: pid} do
      record(pid, "Physics", :node_request, "alice")
      record(pid, "Chemistry", :node_request, "bob")

      clusters = GenServer.call(pid, :all)
      assert length(clusters) == 2
    end

    test "nil user_id does not count toward distinct users", %{pid: pid} do
      record(pid, "Topic Y", :node_request, nil)
      record(pid, "Topic Y", :node_request, nil)
      record(pid, "Topic Y", :node_request, nil)

      {:ok, cluster} = GenServer.call(pid, {:get, "topic y"})
      assert cluster.distinct_users == 0
      refute cluster.converged
    end

    test "mixed tiers contribute to same cluster", %{pid: pid} do
      record(pid, "Dark Energy", :node_request, "alice")
      record(pid, "Dark Energy", :edge_assertion, "bob")
      record(pid, "Dark Energy", :contradiction_flag, "charlie")

      {:ok, cluster} = GenServer.call(pid, {:get, "dark energy"})
      assert cluster.converged == true
      assert cluster.total_signals == 3
    end
  end

  describe "converged_clusters/0" do
    test "returns only converged clusters", %{pid: pid} do
      # Converge one topic
      record(pid, "Converged", :node_request, "a")
      record(pid, "Converged", :node_request, "b")
      record(pid, "Converged", :node_request, "c")

      # Don't converge another
      record(pid, "Not Converged", :node_request, "alice")

      converged = GenServer.call(pid, :converged)
      assert length(converged) == 1
      assert hd(converged).topic == "converged"
    end
  end

  describe "stats/0" do
    test "returns convergence metrics", %{pid: pid} do
      record(pid, "A", :node_request, "u1")
      record(pid, "A", :node_request, "u2")
      record(pid, "A", :node_request, "u3")
      record(pid, "B", :node_request, "u4")

      stats = GenServer.call(pid, :stats)
      assert stats.total_clusters == 2
      assert stats.converged_clusters == 1
      assert stats.total_signals == 4
      assert stats.convergence_rate == 0.5
    end
  end
end
