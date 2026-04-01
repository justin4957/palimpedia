defmodule Palimpedia.Anchor.IngestionTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Anchor.Ingestion

  # A mock graph repository that stores nodes/edges in the test process
  defmodule MockGraphRepo do
    @moduledoc false

    def insert_node(node) do
      node_id = :erlang.unique_integer([:positive])
      inserted = %{node | id: node_id}
      send(self(), {:node_inserted, inserted})
      {:ok, inserted}
    end

    def insert_edge(edge) do
      edge_id = :erlang.unique_integer([:positive])
      inserted = %{edge | id: edge_id}
      send(self(), {:edge_inserted, inserted})
      {:ok, inserted}
    end
  end

  # A mock adapter that returns canned results
  defmodule MockAdapter do
    @behaviour Palimpedia.Anchor.Adapter

    @impl true
    def fetch_entity(identifier, opts), do: fetch_entities([identifier], opts)

    @impl true
    def fetch_entities(_identifiers, _opts) do
      {:ok,
       %{
         entities: [
           %{
             title: "Quantum Mechanics",
             content: "The study of matter at atomic scale.",
             source_id: "mock:Q1",
             properties: %{}
           },
           %{
             title: "General Relativity",
             content: "Einstein's theory of gravitation.",
             source_id: "mock:Q2",
             properties: %{}
           }
         ],
         relationships: [
           %{
             source_id: "mock:Q1",
             target_id: "mock:Q2",
             edge_type: :related_to,
             confidence: 0.9
           }
         ]
       }}
    end

    @impl true
    def search(_query, _opts), do: fetch_entities([], [])
  end

  defmodule FailingAdapter do
    @behaviour Palimpedia.Anchor.Adapter

    @impl true
    def fetch_entity(id, opts), do: fetch_entities([id], opts)

    @impl true
    def fetch_entities(_ids, _opts), do: {:error, :network_error}

    @impl true
    def search(_query, _opts), do: {:error, :network_error}
  end

  describe "ingest_entities/3" do
    test "creates anchor nodes and edges from adapter results" do
      result =
        Ingestion.ingest_entities(MockAdapter, ["Q1", "Q2"], graph_repo: MockGraphRepo)

      assert result.nodes_created == 2
      assert result.edges_created == 1
      assert result.errors == []

      # Verify nodes were inserted with anchor type
      assert_received {:node_inserted, node1}
      assert node1.node_type == :anchor
      assert node1.confidence == 1.0
      assert node1.anchor_distance == 0

      assert_received {:node_inserted, node2}
      assert node2.node_type == :anchor

      # Verify edge was inserted
      assert_received {:edge_inserted, edge}
      assert edge.edge_type == :related_to
      assert edge.confidence == 0.9
    end

    test "handles batch processing" do
      result =
        Ingestion.ingest_entities(MockAdapter, ["Q1", "Q2"],
          graph_repo: MockGraphRepo,
          batch_size: 1
        )

      # Each batch of 1 identifier triggers a fetch_entities call
      # which returns 2 entities, so 2 batches * 2 entities = 4 nodes
      assert result.nodes_created == 4
    end

    test "handles adapter failures gracefully" do
      result =
        Ingestion.ingest_entities(FailingAdapter, ["Q1"], graph_repo: MockGraphRepo)

      assert result.nodes_created == 0
      assert result.edges_created == 0
      assert length(result.errors) > 0
    end
  end

  describe "ingest_search/3" do
    test "ingests entities from a search query" do
      assert {:ok, result} =
               Ingestion.ingest_search(MockAdapter, "quantum", graph_repo: MockGraphRepo)

      assert result.nodes_created == 2
      assert result.edges_created == 1
    end

    test "handles search failures" do
      assert {:ok, result} =
               Ingestion.ingest_search(FailingAdapter, "quantum", graph_repo: MockGraphRepo)

      assert result.nodes_created == 0
      assert length(result.errors) > 0
    end
  end

  describe "insert_fetch_result/2" do
    test "handles relationships with missing target nodes" do
      fetch_result = %{
        entities: [
          %{
            title: "Existing Node",
            content: "This node exists.",
            source_id: "mock:exists",
            properties: %{}
          }
        ],
        relationships: [
          %{
            source_id: "mock:exists",
            target_id: "mock:missing",
            edge_type: :references,
            confidence: 0.5
          }
        ]
      }

      assert {:ok, result} = Ingestion.insert_fetch_result(fetch_result, MockGraphRepo)
      assert result.nodes_created == 1
      assert result.edges_created == 0
      assert length(result.errors) == 1

      [{:missing_target_node, "mock:missing"}] = result.errors
    end
  end
end
