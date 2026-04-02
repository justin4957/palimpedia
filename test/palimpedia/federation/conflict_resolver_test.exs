defmodule Palimpedia.Federation.ConflictResolverTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Federation.ConflictResolver
  alias Palimpedia.Graph.Node

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)

    {:ok, pid} =
      GenServer.start_link(ConflictResolver, [strategy: :anchor_weighted],
        name: :"cr_#{:erlang.unique_integer([:positive])}"
      )

    on_exit(fn ->
      Application.put_env(:palimpedia, :graph_repository, original)
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    %{pid: pid}
  end

  defp detect(pid, remote_nodes, opts \\ []) do
    GenServer.call(pid, {:detect, remote_nodes, opts})
  end

  describe "detect_conflicts/2" do
    test "detects divergent confidence scores", %{pid: pid} do
      # MockGraphRepo has "Quantum Mechanics" at confidence 1.0
      remote_nodes = [
        %Node{title: "Quantum Mechanics", confidence: 0.6, node_type: :anchor}
      ]

      {:ok, conflicts} = detect(pid, remote_nodes, source_instance: "peer-1")

      assert length(conflicts) == 1
      [conflict] = conflicts
      assert conflict.node_title == "Quantum Mechanics"
      assert conflict.instance_scores["local"] == 1.0
      assert conflict.instance_scores["peer-1"] == 0.6
      assert conflict.status == :detected
    end

    test "ignores small divergences below threshold", %{pid: pid} do
      # MockGraphRepo has "Quantum Entanglement" at 0.75
      remote_nodes = [
        %Node{title: "Quantum Entanglement", confidence: 0.74, node_type: :generated}
      ]

      {:ok, conflicts} = detect(pid, remote_nodes)
      assert conflicts == []
    end

    test "ignores nodes not found locally", %{pid: pid} do
      remote_nodes = [
        %Node{title: "Nonexistent Topic", confidence: 0.5, node_type: :generated}
      ]

      {:ok, conflicts} = detect(pid, remote_nodes)
      assert conflicts == []
    end
  end

  describe "resolve/2" do
    test "resolves using anchor_weighted strategy", %{pid: pid} do
      remote_nodes = [
        %Node{title: "Quantum Mechanics", confidence: 0.6, node_type: :anchor}
      ]

      {:ok, [conflict]} = detect(pid, remote_nodes, source_instance: "peer-1")
      {:ok, resolved} = GenServer.call(pid, {:resolve, conflict.id, []})

      assert resolved.status == :resolved
      assert resolved.strategy_used == :anchor_weighted
      assert is_float(resolved.resolved_score)
      assert resolved.resolved_at != nil
    end

    test "returns error for unknown conflict", %{pid: pid} do
      assert {:error, :not_found} = GenServer.call(pid, {:resolve, "nonexistent", []})
    end
  end

  describe "resolve_manually/2" do
    test "sets a manually chosen score", %{pid: pid} do
      remote_nodes = [
        %Node{title: "Quantum Mechanics", confidence: 0.5, node_type: :anchor}
      ]

      {:ok, [conflict]} = detect(pid, remote_nodes, source_instance: "peer-2")
      {:ok, resolved} = GenServer.call(pid, {:resolve_manual, conflict.id, 0.8})

      assert resolved.resolved_score == 0.8
      assert resolved.strategy_used == :manual
      assert resolved.status == :resolved
    end
  end

  describe "list_conflicts/1" do
    test "returns all conflicts", %{pid: pid} do
      detect(pid, [%Node{title: "Quantum Mechanics", confidence: 0.4, node_type: :anchor}],
        source_instance: "a"
      )

      conflicts = GenServer.call(pid, {:list, []})
      assert length(conflicts) >= 1
    end

    test "filters by status", %{pid: pid} do
      detect(pid, [%Node{title: "Quantum Mechanics", confidence: 0.3, node_type: :anchor}],
        source_instance: "b"
      )

      detected = GenServer.call(pid, {:list, [status: :detected]})
      resolved = GenServer.call(pid, {:list, [status: :resolved]})

      assert length(detected) >= 1
      assert length(resolved) == 0
    end
  end

  describe "stats/0" do
    test "tracks detection and resolution counts", %{pid: pid} do
      detect(pid, [%Node{title: "Quantum Mechanics", confidence: 0.2, node_type: :anchor}],
        source_instance: "c"
      )

      stats = GenServer.call(pid, :stats)
      assert stats.total_detected >= 1
      assert stats.pending >= 1
      assert stats.strategy == :anchor_weighted
    end
  end

  describe "resolution strategies" do
    test "anchor_weighted gives more weight to higher confidence", %{pid: pid} do
      detect(pid, [%Node{title: "Quantum Mechanics", confidence: 0.4, node_type: :anchor}],
        source_instance: "d"
      )

      conflicts = GenServer.call(pid, {:list, []})
      [conflict | _] = conflicts

      {:ok, resolved} = GenServer.call(pid, {:resolve, conflict.id, [strategy: :anchor_weighted]})
      # Local is 1.0, remote is 0.4 — anchor-weighted should favor the higher score
      assert resolved.resolved_score > 0.5
    end

    test "average gives equal weight", %{pid: pid} do
      detect(pid, [%Node{title: "Quantum Mechanics", confidence: 0.4, node_type: :anchor}],
        source_instance: "e"
      )

      conflicts = GenServer.call(pid, {:list, []})
      [conflict | _] = conflicts

      {:ok, resolved} = GenServer.call(pid, {:resolve, conflict.id, [strategy: :average]})
      # Average of 1.0 and 0.4 = 0.7
      assert_in_delta resolved.resolved_score, 0.7, 0.01
    end
  end
end
