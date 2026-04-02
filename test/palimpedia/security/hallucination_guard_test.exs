defmodule Palimpedia.Security.HallucinationGuardTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Security.HallucinationGuard

  setup do
    {:ok, pid} =
      GenServer.start_link(HallucinationGuard, [],
        name: :"hg_#{:erlang.unique_integer([:positive])}"
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{pid: pid}
  end

  describe "enforce_confidence_ceiling/3" do
    test "caps ungrounded nodes at 0.5" do
      # No anchor distance, no provenance
      assert HallucinationGuard.enforce_confidence_ceiling(0.9, nil, []) == 0.5
    end

    test "caps nodes with empty provenance at 0.5" do
      assert HallucinationGuard.enforce_confidence_ceiling(0.8, 2, []) == 0.5
    end

    test "allows grounded nodes above 0.5" do
      assert HallucinationGuard.enforce_confidence_ceiling(0.9, 1, ["wikidata:Q1"]) == 0.9
    end

    test "does not cap ungrounded nodes below ceiling" do
      assert HallucinationGuard.enforce_confidence_ceiling(0.3, nil, []) == 0.3
    end

    test "ceiling value is 0.5" do
      assert HallucinationGuard.confidence_ceiling() == 0.5
    end
  end

  describe "record_generation and audit_trail" do
    test "records and retrieves generation audit", %{pid: pid} do
      GenServer.call(pid, {:record_generation, 10, [1, 2, 3], []})

      {:ok, entry} = GenServer.call(pid, {:audit_trail, 10})
      assert entry.context_node_ids == [1, 2, 3]
      assert entry.success == true
      assert entry.timestamp != nil
    end

    test "returns not_found for untracked nodes", %{pid: pid} do
      assert {:error, :not_found} = GenServer.call(pid, {:audit_trail, 999})
    end
  end

  describe "downstream_of" do
    test "returns nodes generated from a context node", %{pid: pid} do
      GenServer.call(pid, {:record_generation, 10, [1, 2], []})
      GenServer.call(pid, {:record_generation, 11, [1, 3], []})
      GenServer.call(pid, {:record_generation, 12, [4, 5], []})

      downstream = GenServer.call(pid, {:downstream_of, 1})
      assert length(downstream) == 2

      gen_ids = Enum.map(downstream, & &1.generated_node_id)
      assert 10 in gen_ids
      assert 11 in gen_ids
      refute 12 in gen_ids
    end
  end

  describe "circuit breaker" do
    test "allows generation when error rate is low", %{pid: pid} do
      GenServer.call(pid, {:record_generation, 10, [1], []})
      GenServer.call(pid, {:record_generation, 11, [1], []})

      assert :ok = GenServer.call(pid, {:check_circuit, [1]})
    end

    test "opens circuit when error rate exceeds threshold", %{pid: pid} do
      # Record mostly failures for context node 1
      for _ <- 1..8 do
        GenServer.call(pid, {:record_failure, [1]})
      end

      for _ <- 1..2 do
        GenServer.call(pid, {:record_generation, :erlang.unique_integer([:positive]), [1], []})
      end

      # Error rate = 8/10 = 0.8 > 0.3 threshold
      assert {:circuit_open, _reason} = GenServer.call(pid, {:check_circuit, [1]})
    end

    test "circuit allows unrelated context nodes", %{pid: pid} do
      for _ <- 1..10 do
        GenServer.call(pid, {:record_failure, [1]})
      end

      # Node 2 has no failures
      assert :ok = GenServer.call(pid, {:check_circuit, [2]})
    end
  end

  describe "stats" do
    test "tracks generation and failure counts", %{pid: pid} do
      GenServer.call(pid, {:record_generation, 10, [1], []})
      GenServer.call(pid, {:record_generation, 11, [2], []})
      GenServer.call(pid, {:record_failure, [3]})

      stats = GenServer.call(pid, :stats)
      assert stats.total_generations == 2
      assert stats.total_failures == 1
      assert_in_delta stats.error_rate, 0.333, 0.01
      assert stats.audit_log_size == 2
    end
  end
end
