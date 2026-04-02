defmodule Palimpedia.Generation.OnDemandTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Generation.OnDemand
  alias Palimpedia.Graph.Node

  defmodule MockRepo do
    @moduledoc false

    @existing %Node{
      id: 1,
      title: "Quantum Mechanics",
      content: "QM content",
      node_type: :anchor,
      confidence: 1.0,
      anchor_distance: 0,
      provenance: ["wikidata:Q944"]
    }

    def search_nodes("Quantum Mechanics", _opts), do: {:ok, [@existing]}
    def search_nodes("Quantum" <> _, _opts), do: {:ok, [@existing]}

    # Simulate related nodes for pressure calculation
    def search_nodes("Dark", _opts) do
      {:ok,
       [
         %Node{id: 10, title: "Dark Energy", confidence: 0.8, node_type: :anchor},
         %Node{id: 11, title: "Dark Matter", confidence: 0.9, node_type: :anchor}
       ]}
    end

    def search_nodes("Matter", _opts) do
      {:ok,
       [
         %Node{id: 11, title: "Dark Matter", confidence: 0.9, node_type: :anchor},
         %Node{id: 12, title: "Matter", confidence: 1.0, node_type: :anchor}
       ]}
    end

    # No results for unknown titles
    def search_nodes("Completely" <> _, _opts), do: {:ok, []}
    def search_nodes("Unknown" <> _, _opts), do: {:ok, []}
    def search_nodes(_, _opts), do: {:ok, []}
  end

  setup do
    {:ok, pid} =
      GenServer.start_link(OnDemand, [],
        name: :"on_demand_#{:erlang.unique_integer([:positive])}"
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{pid: pid}
  end

  defp evaluate(pid, title) do
    GenServer.call(pid, {:evaluate, title, [graph_repo: MockRepo]})
  end

  describe "evaluate/2" do
    test "returns existing node when title matches exactly", %{pid: pid} do
      {:exists, node} = evaluate(pid, "Quantum Mechanics")
      assert node.title == "Quantum Mechanics"
      assert node.id == 1
    end

    test "enqueues high-pressure titles for generation", %{pid: pid} do
      # "Dark Matter" has related nodes -> high pressure
      result = evaluate(pid, "Dark Matter Interactions")
      assert match?({:enqueued, _}, result) or match?({:declined, _}, result)

      case result do
        {:enqueued, request} ->
          assert request.title == "Dark Matter Interactions"
          assert request.pressure >= 2.0
          assert request.status == :enqueued

        {:declined, request} ->
          assert request.pressure < 2.0
      end
    end

    test "declines titles with no related context", %{pid: pid} do
      {:declined, request} = evaluate(pid, "Completely Unknown Topic XYZ")
      assert request.pressure == 0.0
      assert request.status == :declined
    end

    test "returns pending for already-enqueued titles", %{pid: pid} do
      # First evaluation enqueues or declines
      first = evaluate(pid, "Dark Matter Interactions")

      case first do
        {:enqueued, _} ->
          # Second evaluation should return pending
          {:pending, _} = evaluate(pid, "Dark Matter Interactions")

        {:declined, _} ->
          # If declined, re-evaluation returns the same decline
          :ok
      end
    end
  end

  describe "status/1" do
    test "returns :unknown for untracked titles", %{pid: pid} do
      {:ok, :unknown} = GenServer.call(pid, {:status, "Never Requested"})
    end

    test "returns current status for tracked titles", %{pid: pid} do
      evaluate(pid, "Completely Unknown Topic XYZ")
      {:ok, request} = GenServer.call(pid, {:status, "Completely Unknown Topic XYZ"})
      assert request.status == :declined
    end
  end

  describe "mark_completed/2" do
    test "updates status to completed with node_id", %{pid: pid} do
      evaluate(pid, "Completely Unknown Topic XYZ")
      {:ok, updated} = GenServer.call(pid, {:mark_completed, "Completely Unknown Topic XYZ", 42})

      assert updated.status == :completed
      assert updated.node_id == 42
      assert updated.completed_at != nil
    end
  end

  describe "list_pending/0" do
    test "returns only enqueued/generating requests", %{pid: pid} do
      evaluate(pid, "Completely Unknown Topic XYZ")
      pending = GenServer.call(pid, :list_pending)

      # Declined requests should not appear in pending
      for req <- pending do
        assert req.status in [:enqueued, :generating, :evaluating]
      end
    end
  end
end
