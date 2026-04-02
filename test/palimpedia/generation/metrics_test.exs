defmodule Palimpedia.Generation.MetricsTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Generation.Metrics
  alias Palimpedia.Graph.Node

  setup do
    {:ok, pid} = GenServer.start_link(Metrics, [], name: :test_metrics)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{pid: pid}
  end

  defp snapshot(pid), do: GenServer.call(pid, :snapshot)

  describe "record_success/1" do
    test "increments generated count and tracks tokens", %{pid: pid} do
      result = %{
        node: %Node{confidence: 0.8},
        token_usage: %{input: 500, output: 200},
        estimated_cost: 0.001
      }

      GenServer.cast(pid, {:success, result})
      Process.sleep(10)

      snap = snapshot(pid)
      assert snap.total_generated == 1
      assert snap.total_failed == 0
      assert snap.success_rate == 1.0
      assert snap.total_input_tokens == 500
      assert snap.total_output_tokens == 200
      assert snap.total_cost == 0.001
      assert snap.avg_confidence == 0.8
    end

    test "accumulates across multiple generations", %{pid: pid} do
      for i <- 1..3 do
        GenServer.cast(
          pid,
          {:success,
           %{
             node: %Node{confidence: 0.5 + i * 0.1},
             token_usage: %{input: 100, output: 50},
             estimated_cost: 0.0005
           }}
        )
      end

      Process.sleep(20)
      snap = snapshot(pid)
      assert snap.total_generated == 3
      assert snap.total_input_tokens == 300
      assert snap.total_cost > 0.001
    end
  end

  describe "record_failure/1" do
    test "increments failure count", %{pid: pid} do
      GenServer.cast(pid, {:failure, :timeout})
      Process.sleep(10)

      snap = snapshot(pid)
      assert snap.total_failed == 1
      assert snap.total_generated == 0
      assert snap.success_rate == 0.0
    end
  end

  describe "success_rate" do
    test "computes correct rate", %{pid: pid} do
      GenServer.cast(
        pid,
        {:success,
         %{node: %Node{confidence: 0.5}, token_usage: %{input: 0, output: 0}, estimated_cost: 0}}
      )

      GenServer.cast(
        pid,
        {:success,
         %{node: %Node{confidence: 0.5}, token_usage: %{input: 0, output: 0}, estimated_cost: 0}}
      )

      GenServer.cast(pid, {:failure, :error})
      Process.sleep(20)

      snap = snapshot(pid)
      assert_in_delta snap.success_rate, 0.666, 0.01
    end
  end

  describe "reset/0" do
    test "clears all metrics", %{pid: pid} do
      GenServer.cast(
        pid,
        {:success,
         %{
           node: %Node{confidence: 0.5},
           token_usage: %{input: 100, output: 50},
           estimated_cost: 0.001
         }}
      )

      Process.sleep(10)

      GenServer.call(pid, :reset)
      snap = snapshot(pid)

      assert snap.total_generated == 0
      assert snap.total_failed == 0
      assert snap.total_input_tokens == 0
    end
  end
end
