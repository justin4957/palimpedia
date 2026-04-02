defmodule Palimpedia.Generation.BatchWorkerTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Generation.BatchWorker

  describe "start_link and status" do
    test "starts disabled and reports status" do
      {:ok, pid} =
        GenServer.start_link(BatchWorker, [enabled: false], name: :test_batch_status)

      status = GenServer.call(pid, :status)
      assert status.enabled == false
      assert status.total_processed == 0
      assert status.total_succeeded == 0
      assert status.total_failed == 0
      assert status.last_run_at == nil
      assert status.batch_size == 5

      GenServer.stop(pid)
    end
  end

  describe "process_batch with empty queue" do
    test "run_now with no queue entries does nothing" do
      {:ok, pid} =
        GenServer.start_link(BatchWorker, [enabled: false], name: :test_batch_empty)

      GenServer.cast(pid, :run_now)
      Process.sleep(50)

      status = GenServer.call(pid, :status)
      # No entries processed since queue GenServer isn't available
      assert status.total_processed == 0
      assert status.last_run_at != nil

      GenServer.stop(pid)
    end
  end

  describe "configuration" do
    test "respects custom batch_size and max_retries" do
      {:ok, pid} =
        GenServer.start_link(
          BatchWorker,
          [enabled: false, batch_size: 10, max_retries: 5],
          name: :test_batch_config
        )

      status = GenServer.call(pid, :status)
      assert status.batch_size == 10

      GenServer.stop(pid)
    end
  end
end
