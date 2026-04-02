defmodule Palimpedia.Confidence.ProvenanceExplorerTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Confidence.ProvenanceExplorer

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "trace_node/2" do
    test "returns rich trace for an anchor node" do
      {:ok, result} = ProvenanceExplorer.trace_node(1)

      assert result.node_id == 1
      assert result.node_title == "Quantum Mechanics"
      assert result.grounded == true
      assert result.anchor_distance == 0
      assert result.citation_loop == false
      assert is_list(result.provenance_path)
      assert length(result.provenance_path) >= 2
    end

    test "returns rich trace for a generated node" do
      {:ok, result} = ProvenanceExplorer.trace_node(2)

      assert result.node_id == 2
      assert result.grounded == true
      assert result.anchor_distance == 1
      assert is_list(result.anchor_sources)
    end

    test "returns error for unknown node" do
      assert {:error, :not_found} = ProvenanceExplorer.trace_node(999)
    end

    test "provenance path includes node info and anchor sources" do
      {:ok, result} = ProvenanceExplorer.trace_node(1)

      path = result.provenance_path
      assert hd(path) =~ "Quantum Mechanics"
      assert Enum.any?(path, &String.contains?(&1, "hop"))
    end
  end

  describe "audit/1" do
    test "returns audit result with traceability rate" do
      {:ok, audit} = ProvenanceExplorer.audit()

      assert is_integer(audit.total_nodes)
      assert is_integer(audit.traceable_nodes)
      assert is_float(audit.traceability_rate)
      assert audit.traceability_rate >= 0.0 and audit.traceability_rate <= 1.0
      assert is_boolean(audit.passes_audit)
      assert is_list(audit.broken_chains)
      assert is_list(audit.citation_loops)
    end

    test "passes_audit is true when rate >= 90%" do
      {:ok, audit} = ProvenanceExplorer.audit()

      if audit.traceability_rate >= 0.9 do
        assert audit.passes_audit == true
      else
        assert audit.passes_audit == false
      end
    end
  end

  describe "find_broken_chains/1" do
    test "returns list of broken chain nodes" do
      {:ok, broken} = ProvenanceExplorer.find_broken_chains()

      assert is_list(broken)

      for node_info <- broken do
        assert Map.has_key?(node_info, :node_id)
        assert Map.has_key?(node_info, :node_title)
        assert Map.has_key?(node_info, :claimed_provenance)
      end
    end
  end
end
