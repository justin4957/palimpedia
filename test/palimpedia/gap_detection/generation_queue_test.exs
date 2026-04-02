defmodule Palimpedia.GapDetection.GenerationQueueTest do
  use ExUnit.Case, async: false

  alias Palimpedia.GapDetection.GenerationQueue

  setup do
    # Start a fresh queue for each test with unique name
    name = :"queue_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = GenServer.start_link(GenerationQueue, [budget_per_hour: 100], name: name)
    # Override the module-level name temporarily — we call the pid directly
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{pid: pid}
  end

  defp call(pid, msg), do: GenServer.call(pid, msg)

  defp sample_gap(priority, opts \\ []) do
    %{
      gap_type: Keyword.get(opts, :gap_type, :structural_hole),
      priority: priority,
      suggested_title: Keyword.get(opts, :title, nil),
      context: Keyword.get(opts, :context, %{})
    }
  end

  describe "enqueue and dequeue" do
    test "enqueues a gap and dequeues it", %{pid: pid} do
      {:ok, entry} = call(pid, {:enqueue, sample_gap(5.0, title: "Test Gap")})

      assert entry.id != nil
      assert entry.priority == 5.0
      assert entry.status == :pending
      assert entry.suggested_title == "Test Gap"
      assert entry.demand_count == 0

      {:ok, dequeued} = call(pid, :dequeue)
      assert dequeued.id == entry.id
      assert dequeued.status == :processing
    end

    test "dequeues highest priority first", %{pid: pid} do
      call(pid, {:enqueue, sample_gap(3.0, title: "Low")})
      call(pid, {:enqueue, sample_gap(10.0, title: "High")})
      call(pid, {:enqueue, sample_gap(6.0, title: "Medium")})

      {:ok, first} = call(pid, :dequeue)
      assert first.priority == 10.0
      assert first.suggested_title == "High"

      {:ok, second} = call(pid, :dequeue)
      assert second.priority == 6.0

      {:ok, third} = call(pid, :dequeue)
      assert third.priority == 3.0
    end

    test "returns :empty when no pending entries", %{pid: pid} do
      assert {:ok, :empty} = call(pid, :dequeue)
    end

    test "enqueue_batch adds multiple gaps", %{pid: pid} do
      gaps = [sample_gap(5.0), sample_gap(8.0), sample_gap(2.0)]
      {:ok, entries} = call(pid, {:enqueue_batch, gaps})

      assert length(entries) == 3
      assert call(pid, :depth) == 3
    end
  end

  describe "demand boost" do
    test "boosts priority for matching title", %{pid: pid} do
      call(pid, {:enqueue, sample_gap(5.0, title: "Quantum and Relativity")})

      {:ok, matched} = call(pid, {:boost, "Quantum", 3.0})
      assert matched == 1

      [entry] = call(pid, :list_pending)
      assert entry.priority == 8.0
      assert entry.demand_count == 1
    end

    test "multiple boosts stack", %{pid: pid} do
      call(pid, {:enqueue, sample_gap(5.0, title: "Physics Bridge")})

      call(pid, {:boost, "Physics", 2.0})
      call(pid, {:boost, "Physics", 2.0})
      call(pid, {:boost, "Physics", 2.0})

      [entry] = call(pid, :list_pending)
      assert entry.priority == 11.0
      assert entry.demand_count == 3
    end

    test "boost does not affect entries without matching title", %{pid: pid} do
      call(pid, {:enqueue, sample_gap(5.0, title: "Quantum")})
      call(pid, {:enqueue, sample_gap(3.0, title: "Philosophy")})

      {:ok, matched} = call(pid, {:boost, "Quantum", 10.0})
      assert matched == 1

      entries = call(pid, :list_pending)
      quantum = Enum.find(entries, &(&1.suggested_title == "Quantum"))
      philosophy = Enum.find(entries, &(&1.suggested_title == "Philosophy"))

      assert quantum.priority == 15.0
      assert philosophy.priority == 3.0
    end

    test "boost returns 0 when no titles match", %{pid: pid} do
      call(pid, {:enqueue, sample_gap(5.0, title: "Physics")})
      {:ok, matched} = call(pid, {:boost, "Nonexistent", 5.0})
      assert matched == 0
    end
  end

  describe "budget caps" do
    test "dequeue returns :budget_exhausted when limit reached", %{pid: pid} do
      # Start a queue with budget of 2
      GenServer.stop(pid)
      {:ok, pid} = GenServer.start_link(GenerationQueue, [budget_per_hour: 2], name: :budget_test)

      call(pid, {:enqueue, sample_gap(5.0)})
      call(pid, {:enqueue, sample_gap(4.0)})
      call(pid, {:enqueue, sample_gap(3.0)})

      # Dequeue and complete 2 entries
      {:ok, e1} = call(pid, :dequeue)
      call(pid, {:set_status, e1.id, :completed})

      {:ok, e2} = call(pid, :dequeue)
      call(pid, {:set_status, e2.id, :completed})

      # Third dequeue should be budget-exhausted
      assert {:ok, :budget_exhausted} = call(pid, :dequeue)

      GenServer.stop(pid)
    end
  end

  describe "status tracking" do
    test "complete marks entry as completed", %{pid: pid} do
      {:ok, entry} = call(pid, {:enqueue, sample_gap(5.0)})
      {:ok, _} = call(pid, :dequeue)
      :ok = call(pid, {:set_status, entry.id, :completed})

      stats = call(pid, :stats)
      assert stats.completed_this_hour == 1
      assert stats.depth == 0
    end

    test "fail marks entry as failed", %{pid: pid} do
      {:ok, entry} = call(pid, {:enqueue, sample_gap(5.0)})
      {:ok, _} = call(pid, :dequeue)
      :ok = call(pid, {:set_status, entry.id, :failed})

      # Failed entries don't count toward budget
      assert call(pid, :depth) == 0
    end
  end

  describe "monitoring" do
    test "stats returns queue metrics", %{pid: pid} do
      call(pid, {:enqueue, sample_gap(5.0)})
      call(pid, {:enqueue, sample_gap(3.0)})

      stats = call(pid, :stats)
      assert stats.depth == 2
      assert stats.processing == 0
      assert stats.completed_this_hour == 0
      assert stats.budget_remaining == 100
      assert stats.oldest_entry != nil
    end

    test "depth returns pending count only", %{pid: pid} do
      call(pid, {:enqueue, sample_gap(5.0)})
      call(pid, {:enqueue, sample_gap(3.0)})
      call(pid, :dequeue)

      assert call(pid, :depth) == 1
    end

    test "list_pending returns sorted entries", %{pid: pid} do
      call(pid, {:enqueue, sample_gap(2.0, title: "Low")})
      call(pid, {:enqueue, sample_gap(9.0, title: "High")})
      call(pid, {:enqueue, sample_gap(5.0, title: "Mid")})

      pending = call(pid, :list_pending)
      assert length(pending) == 3
      assert hd(pending).suggested_title == "High"
      assert List.last(pending).suggested_title == "Low"
    end
  end

  describe "context extraction" do
    test "extracts node IDs from orphan context", %{pid: pid} do
      gap = %{gap_type: :orphan, priority: 5.0, context: %{node_id: 42}, suggested_title: nil}
      {:ok, entry} = call(pid, {:enqueue, gap})
      assert entry.context_node_ids == [42]
    end

    test "extracts node IDs from structural hole context", %{pid: pid} do
      gap = %{
        gap_type: :structural_hole,
        priority: 10.0,
        context: %{node_a_id: 1, node_b_id: 2},
        suggested_title: "A and B"
      }

      {:ok, entry} = call(pid, {:enqueue, gap})
      assert entry.context_node_ids == [1, 2]
    end
  end
end
