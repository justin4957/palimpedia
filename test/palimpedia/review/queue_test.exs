defmodule Palimpedia.Review.QueueTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Review.Queue, as: ReviewQueue
  alias Palimpedia.Graph.Node

  setup do
    {:ok, pid} =
      GenServer.start_link(ReviewQueue, [],
        name: :"review_#{:erlang.unique_integer([:positive])}"
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{pid: pid}
  end

  defp submit(pid, node_id, title, reason) do
    GenServer.call(pid, {:submit, node_id, title, reason, []})
  end

  describe "submit/4" do
    test "creates a review item", %{pid: pid} do
      {:ok, item} = submit(pid, 1, "Quantum Entanglement", :high_confidence)

      assert item.id != nil
      assert item.node_id == 1
      assert item.node_title == "Quantum Entanglement"
      assert item.reason == :high_confidence
      assert item.status == :pending
      assert item.submitted_at != nil
    end

    test "rejects duplicate pending submissions", %{pid: pid} do
      {:ok, _} = submit(pid, 1, "QM", :high_confidence)
      {:ok, result} = submit(pid, 1, "QM", :high_traffic)

      assert result == :already_queued
    end

    test "allows resubmission after review", %{pid: pid} do
      {:ok, item} = submit(pid, 1, "QM", :high_confidence)
      GenServer.call(pid, {:decide, item.id, :approved, []})

      {:ok, new_item} = submit(pid, 1, "QM", :high_traffic)
      assert new_item.id != item.id
    end
  end

  describe "list_pending/0" do
    test "returns pending items ordered by submission time", %{pid: pid} do
      submit(pid, 1, "First", :high_confidence)
      submit(pid, 2, "Second", :high_traffic)

      items = GenServer.call(pid, :list_pending)
      assert length(items) == 2
      assert hd(items).node_title == "First"
    end

    test "excludes approved/rejected items", %{pid: pid} do
      {:ok, item} = submit(pid, 1, "To approve", :high_confidence)
      submit(pid, 2, "Pending", :high_traffic)

      GenServer.call(pid, {:decide, item.id, :approved, []})

      items = GenServer.call(pid, :list_pending)
      assert length(items) == 1
      assert hd(items).node_title == "Pending"
    end
  end

  describe "approve/reject/flag" do
    test "approve sets status and records timestamp", %{pid: pid} do
      {:ok, item} = submit(pid, 1, "QM", :high_confidence)
      {:ok, approved} = GenServer.call(pid, {:decide, item.id, :approved, [note: "Looks good"]})

      assert approved.status == :approved
      assert approved.reviewed_at != nil
      assert approved.reviewer_note == "Looks good"
    end

    test "reject sets status", %{pid: pid} do
      {:ok, item} = submit(pid, 1, "QM", :high_confidence)
      {:ok, rejected} = GenServer.call(pid, {:decide, item.id, :rejected, [note: "Inaccurate"]})

      assert rejected.status == :rejected
    end

    test "flag sets status", %{pid: pid} do
      {:ok, item} = submit(pid, 1, "QM", :high_confidence)
      {:ok, flagged} = GenServer.call(pid, {:decide, item.id, :flagged, []})

      assert flagged.status == :flagged
    end

    test "returns error for unknown ID", %{pid: pid} do
      assert {:error, :not_found} = GenServer.call(pid, {:decide, "nonexistent", :approved, []})
    end
  end

  describe "stats/0" do
    test "tracks review metrics", %{pid: pid} do
      {:ok, a} = submit(pid, 1, "A", :high_confidence)
      {:ok, b} = submit(pid, 2, "B", :high_confidence)
      {:ok, c} = submit(pid, 3, "C", :high_confidence)

      GenServer.call(pid, {:decide, a.id, :approved, []})
      GenServer.call(pid, {:decide, b.id, :rejected, []})
      GenServer.call(pid, {:decide, c.id, :flagged, []})

      stats = GenServer.call(pid, :stats)
      assert stats.pending == 0
      assert stats.total_approved == 1
      assert stats.total_rejected == 1
      assert stats.total_flagged == 1
      assert stats.approval_rate == 0.5
      assert stats.avg_latency_ms != nil
    end
  end

  describe "check_and_submit/2" do
    test "submits high-confidence generated nodes" do
      node = %Node{
        id: 50,
        title: "High Confidence",
        node_type: :generated,
        confidence: 0.85
      }

      result = ReviewQueue.check_and_submit(node)
      assert match?({:ok, %{reason: :high_confidence}}, result)
    end

    test "submits high-traffic nodes" do
      node = %Node{
        id: 51,
        title: "Popular",
        node_type: :generated,
        confidence: 0.3
      }

      result = ReviewQueue.check_and_submit(node, traffic_count: 15)
      assert match?({:ok, %{reason: :high_traffic}}, result)
    end

    test "skips anchor nodes" do
      node = %Node{
        id: 52,
        title: "Anchor",
        node_type: :anchor,
        confidence: 1.0
      }

      assert ReviewQueue.check_and_submit(node) == :skip
    end

    test "skips low-confidence low-traffic nodes" do
      node = %Node{
        id: 53,
        title: "Uninteresting",
        node_type: :generated,
        confidence: 0.2
      }

      assert ReviewQueue.check_and_submit(node) == :skip
    end
  end
end
