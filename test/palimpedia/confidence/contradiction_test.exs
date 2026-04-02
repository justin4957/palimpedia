defmodule Palimpedia.Confidence.ContradictionTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Confidence.Contradiction

  setup do
    {:ok, pid} = GenServer.start_link(Contradiction, [], name: :test_contradiction_store)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{pid: pid}
  end

  defp flag(pid, a, b, desc, opts \\ []) do
    GenServer.call(pid, {:flag, a, b, desc, opts})
  end

  describe "flag/4" do
    test "creates a contradiction record", %{pid: pid} do
      {:ok, c} = flag(pid, 1, 2, "Conflicting dates")

      assert c.id != nil
      assert c.node_a_id == 1
      assert c.node_b_id == 2
      assert c.description == "Conflicting dates"
      assert c.status == :open
      assert c.severity == :medium
      assert c.flagged_by == :user
    end

    test "supports custom severity and flagged_by", %{pid: pid} do
      {:ok, c} = flag(pid, 1, 2, "High severity", severity: :high, flagged_by: :system)

      assert c.severity == :high
      assert c.flagged_by == :system
    end

    test "assigns unique IDs", %{pid: pid} do
      {:ok, c1} = flag(pid, 1, 2, "First")
      {:ok, c2} = flag(pid, 3, 4, "Second")

      assert c1.id != c2.id
    end
  end

  describe "list_open/1" do
    test "returns all open contradictions", %{pid: pid} do
      flag(pid, 1, 2, "A")
      flag(pid, 3, 4, "B")

      {:ok, open} = GenServer.call(pid, {:list_open, []})
      assert length(open) == 2
    end

    test "filters by node_id", %{pid: pid} do
      flag(pid, 1, 2, "Involves node 1")
      flag(pid, 3, 4, "Does not involve node 1")

      {:ok, filtered} = GenServer.call(pid, {:list_open, [node_id: 1]})
      assert length(filtered) == 1
      assert hd(filtered).node_a_id == 1
    end

    test "excludes resolved contradictions", %{pid: pid} do
      {:ok, c} = flag(pid, 1, 2, "To be resolved")
      GenServer.call(pid, {:resolve, c.id, :confirmed})

      {:ok, open} = GenServer.call(pid, {:list_open, []})
      assert open == []
    end
  end

  describe "count_for_node/1" do
    test "counts open contradictions involving a node", %{pid: pid} do
      flag(pid, 1, 2, "A")
      flag(pid, 1, 3, "B")
      flag(pid, 4, 5, "Unrelated")

      count = GenServer.call(pid, {:count_for_node, 1})
      assert count == 2
    end

    test "counts both sides (node_a and node_b)", %{pid: pid} do
      flag(pid, 10, 1, "As target")

      count = GenServer.call(pid, {:count_for_node, 1})
      assert count == 1
    end
  end

  describe "resolve/2" do
    test "confirmed sets status to resolved", %{pid: pid} do
      {:ok, c} = flag(pid, 1, 2, "To resolve")
      {:ok, resolved} = GenServer.call(pid, {:resolve, c.id, :confirmed})

      assert resolved.status == :resolved
    end

    test "dismissed sets status to dismissed", %{pid: pid} do
      {:ok, c} = flag(pid, 1, 2, "To dismiss")
      {:ok, dismissed} = GenServer.call(pid, {:resolve, c.id, :dismissed})

      assert dismissed.status == :dismissed
    end

    test "returns error for unknown ID", %{pid: pid} do
      assert {:error, :not_found} = GenServer.call(pid, {:resolve, "nonexistent", :confirmed})
    end
  end
end
