defmodule Palimpedia.Export.SnapshotTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Export.Snapshot

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)

    {:ok, pid} =
      GenServer.start_link(Snapshot, [], name: :"snap_#{:erlang.unique_integer([:positive])}")

    on_exit(fn ->
      Application.put_env(:palimpedia, :graph_repository, original)
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    %{pid: pid}
  end

  describe "create/2" do
    test "creates an RDF snapshot", %{pid: pid} do
      {:ok, meta} = GenServer.call(pid, {:create, :rdf, []})

      assert meta.format == :rdf
      assert meta.node_count > 0
      assert meta.size_bytes > 0
      assert meta.version == 1
    end

    test "creates a JSON-LD snapshot", %{pid: pid} do
      {:ok, meta} = GenServer.call(pid, {:create, :json_ld, []})

      assert meta.format == :json_ld
      assert meta.node_count > 0
    end

    test "versions increment", %{pid: pid} do
      {:ok, m1} = GenServer.call(pid, {:create, :rdf, []})
      {:ok, m2} = GenServer.call(pid, {:create, :rdf, []})

      assert m2.version == m1.version + 1
    end
  end

  describe "list_snapshots/0" do
    test "lists created snapshots", %{pid: pid} do
      GenServer.call(pid, {:create, :rdf, []})
      GenServer.call(pid, {:create, :json_ld, []})

      snapshots = GenServer.call(pid, :list)
      assert length(snapshots) == 2
    end
  end

  describe "get_snapshot/1" do
    test "returns snapshot content", %{pid: pid} do
      {:ok, meta} = GenServer.call(pid, {:create, :rdf, []})
      {:ok, _meta, content} = GenServer.call(pid, {:get, meta.id})

      assert is_binary(content)
      assert String.contains?(content, "palimpedia")
    end

    test "returns error for unknown snapshot", %{pid: pid} do
      assert {:error, :not_found} = GenServer.call(pid, {:get, "nonexistent"})
    end
  end

  describe "diff/2" do
    test "computes diff between snapshots", %{pid: pid} do
      {:ok, m1} = GenServer.call(pid, {:create, :rdf, []})
      {:ok, m2} = GenServer.call(pid, {:create, :rdf, []})

      {:ok, diff} = GenServer.call(pid, {:diff, m1.id, m2.id})

      assert diff.version_a == m1.version
      assert diff.version_b == m2.version
      assert is_integer(diff.node_delta)
      assert is_integer(diff.size_delta)
    end
  end
end
