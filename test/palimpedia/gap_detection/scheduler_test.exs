defmodule Palimpedia.GapDetection.SchedulerTest do
  use ExUnit.Case, async: false

  alias Palimpedia.GapDetection.Scheduler

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "start_link and status" do
    test "starts with disabled scheduler and no results" do
      {:ok, pid} = GenServer.start_link(Scheduler, [enabled: false], name: :test_scheduler_status)

      status = GenServer.call(pid, :status)
      assert status.enabled == false
      assert status.last_run_at == nil
      assert status.gap_count == nil

      GenServer.stop(pid)
    end
  end

  describe "run_now" do
    test "triggers immediate analysis and stores result" do
      {:ok, pid} = GenServer.start_link(Scheduler, [enabled: false], name: :test_scheduler_run)

      GenServer.cast(pid, :run_now)
      Process.sleep(100)

      result = GenServer.call(pid, :latest_result)
      assert result != nil
      assert result.stats.total_gaps >= 0
      assert result.analyzed_at != nil

      status = GenServer.call(pid, :status)
      assert status.last_run_at != nil

      GenServer.stop(pid)
    end
  end
end
