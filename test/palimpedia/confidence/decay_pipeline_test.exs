defmodule Palimpedia.Confidence.DecayPipelineTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Confidence.DecayPipeline
  alias Palimpedia.Graph.Node

  defmodule DecayMockRepo do
    @moduledoc false

    @old_node %Node{
      id: 10,
      title: "Old Document",
      node_type: :generated,
      confidence: 0.8,
      anchor_distance: 2,
      provenance: ["wikidata:Q1"],
      generated_at: DateTime.utc_now() |> DateTime.add(-100 * 86400, :second)
    }

    @recent_node %Node{
      id: 11,
      title: "Recent Document",
      node_type: :generated,
      confidence: 0.9,
      anchor_distance: 1,
      provenance: ["wikidata:Q2"],
      generated_at: DateTime.utc_now() |> DateTime.add(-1 * 86400, :second)
    }

    @stale_low_conf %Node{
      id: 12,
      title: "Stale Low Confidence",
      node_type: :generated,
      confidence: 0.1,
      anchor_distance: 5,
      provenance: [],
      generated_at: DateTime.utc_now() |> DateTime.add(-200 * 86400, :second)
    }

    def find_generated_nodes(_opts), do: {:ok, [@old_node, @recent_node]}

    def find_stale_nodes(_days, _opts), do: {:ok, [@stale_low_conf]}

    def update_confidence(node_id, confidence, anchor_distance) do
      send(self(), {:confidence_updated, node_id, confidence, anchor_distance})

      {:ok,
       %Node{
         id: node_id,
         title: "Updated",
         confidence: confidence,
         anchor_distance: anchor_distance,
         node_type: :generated
       }}
    end

    def subgraph(_, _) do
      {:ok, [@old_node, @recent_node], []}
    end

    def shortest_anchor_distance(_, _), do: {:ok, 2}
    def anchor_sources(_, _), do: {:ok, []}
  end

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, DecayMockRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "start_link and status" do
    test "starts disabled with no sweep history" do
      {:ok, pid} =
        GenServer.start_link(DecayPipeline, [enabled: false],
          name: :"decay_#{:erlang.unique_integer([:positive])}"
        )

      status = GenServer.call(pid, :status)
      assert status.enabled == false
      assert status.last_sweep == nil
      assert status.total_sweeps == 0

      GenServer.stop(pid)
    end
  end

  describe "run_sweep" do
    test "applies decay and flags stale documents" do
      {:ok, pid} =
        GenServer.start_link(DecayPipeline, [enabled: false],
          name: :"decay_sweep_#{:erlang.unique_integer([:positive])}"
        )

      {:ok, result} = GenServer.call(pid, :run_sweep)

      assert result.decayed >= 0
      assert result.errors == 0

      status = GenServer.call(pid, :status)
      assert status.last_sweep != nil
      assert status.last_sweep_at != nil
      assert status.total_sweeps == 1

      GenServer.stop(pid)
    end

    test "decays old nodes (decayed count > 0)" do
      {:ok, pid} =
        GenServer.start_link(DecayPipeline, [enabled: false],
          name: :"decay_update_#{:erlang.unique_integer([:positive])}"
        )

      {:ok, result} = GenServer.call(pid, :run_sweep)

      # The old node (100 days) should have had its confidence reduced
      assert result.decayed > 0

      GenServer.stop(pid)
    end
  end

  describe "trigger_anchor_update" do
    test "cascades re-evaluation from anchor" do
      {:ok, pid} =
        GenServer.start_link(DecayPipeline, [enabled: false],
          name: :"decay_cascade_#{:erlang.unique_integer([:positive])}"
        )

      {:ok, result} =
        GenServer.call(pid, {:anchor_update, 1, [graph_repo: DecayMockRepo, hops: 2]})

      # The subgraph recalculation should have updated some nodes
      assert is_integer(result.updated)

      GenServer.stop(pid)
    end
  end
end
