defmodule Palimpedia.Generation.RevisionHistoryTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Generation.RevisionHistory

  setup do
    {:ok, pid} =
      GenServer.start_link(RevisionHistory, [],
        name: :"revhist_#{:erlang.unique_integer([:positive])}"
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{pid: pid}
  end

  defp record(pid, node_id, title, trigger, old, new, old_conf, new_conf) do
    GenServer.call(pid, {:record, node_id, title, trigger, old, new, old_conf, new_conf})
  end

  describe "record/7" do
    test "creates a revision with diff summary", %{pid: pid} do
      {:ok, rev} = record(pid, 1, "Test Node", :contradiction, "old text", "new text", 0.5, 0.7)

      assert rev.id != nil
      assert rev.node_id == 1
      assert rev.node_title == "Test Node"
      assert rev.trigger == :contradiction
      assert rev.old_content == "old text"
      assert rev.new_content == "new text"
      assert rev.diff_summary =~ "content revised"
      assert rev.diff_summary =~ "confidence +0.2"
    end

    test "diff shows no changes when content and confidence are same", %{pid: pid} do
      {:ok, rev} = record(pid, 1, "Node", :manual, "same", "same", 0.5, 0.5)
      assert rev.diff_summary == "no changes"
    end

    test "diff shows confidence decrease", %{pid: pid} do
      {:ok, rev} = record(pid, 1, "Node", :staleness, "text", "text", 0.8, 0.5)
      assert rev.diff_summary =~ "confidence -0.3"
    end
  end

  describe "history_for/1" do
    test "returns revisions for a node, newest first", %{pid: pid} do
      record(pid, 1, "Node", :contradiction, "v1", "v2", 0.5, 0.6)
      record(pid, 1, "Node", :anchor_update, "v2", "v3", 0.6, 0.7)
      record(pid, 2, "Other", :manual, "a", "b", 0.3, 0.4)

      history = GenServer.call(pid, {:history_for, 1})
      assert length(history) == 2
      assert hd(history).new_content == "v3"
    end
  end

  describe "recent/1" do
    test "returns most recent revisions", %{pid: pid} do
      for i <- 1..5 do
        record(pid, i, "Node #{i}", :contradiction, "old", "new", 0.5, 0.6)
      end

      recent = GenServer.call(pid, {:recent, 3})
      assert length(recent) == 3
    end
  end

  describe "stats/0" do
    test "returns counts by trigger", %{pid: pid} do
      record(pid, 1, "A", :contradiction, "o", "n", 0.5, 0.6)
      record(pid, 2, "B", :contradiction, "o", "n", 0.5, 0.6)
      record(pid, 3, "C", :anchor_update, "o", "n", 0.5, 0.6)

      stats = GenServer.call(pid, :stats)
      assert stats.total == 3
      assert stats.by_trigger[:contradiction] == 2
      assert stats.by_trigger[:anchor_update] == 1
    end
  end
end
