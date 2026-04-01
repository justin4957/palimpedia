defmodule Palimpedia.Generation.PipelineTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Generation.Pipeline
  alias Palimpedia.Graph.{Node, Edge}

  @llm_response Jason.encode!(%{
                  "content" => [
                    %{
                      "type" => "text",
                      "text" =>
                        Jason.encode!(%{
                          "title" => "Quantum Entanglement",
                          "content" =>
                            "Quantum entanglement is a phenomenon where two particles become linked.",
                          "claims" => [
                            %{
                              "text" => "Entangled particles share correlated quantum states.",
                              "confidence" => 0.9,
                              "provenance" => ["wikidata:Q944"]
                            },
                            %{
                              "text" =>
                                "Measurement of one particle instantly affects the other.",
                              "confidence" => 0.8,
                              "provenance" => ["wikidata:Q944"]
                            }
                          ],
                          "edges" => [
                            %{
                              "target_title" => "Quantum Mechanics",
                              "edge_type" => "specializes",
                              "confidence" => 0.95
                            }
                          ],
                          "contradictions" => [
                            %{
                              "existing_node_title" => "Local Realism",
                              "description" => "Entanglement violates local realism"
                            }
                          ]
                        })
                    }
                  ],
                  "model" => "claude-haiku-4-5-20251001",
                  "usage" => %{"input_tokens" => 800, "output_tokens" => 400},
                  "stop_reason" => "end_turn"
                })

  defmodule MockGraphRepo do
    @moduledoc false

    def insert_node(node) do
      {:ok, %{node | id: :erlang.unique_integer([:positive])}}
    end

    def insert_edge(edge) do
      {:ok, %{edge | id: :erlang.unique_integer([:positive])}}
    end

    def search_nodes("Quantum Mechanics", _opts) do
      {:ok,
       [
         %Node{
           id: 100,
           title: "Quantum Mechanics",
           node_type: :anchor,
           confidence: 1.0,
           provenance: ["wikidata:Q944"]
         }
       ]}
    end

    def search_nodes(_, _opts), do: {:ok, []}

    def subgraph(_node_id, _hops) do
      {:ok,
       [
         %Node{
           id: 100,
           title: "Quantum Mechanics",
           node_type: :anchor,
           confidence: 1.0,
           anchor_distance: 0,
           provenance: ["wikidata:Q944"]
         },
         %Node{
           id: 101,
           title: "Wave Function",
           node_type: :generated,
           confidence: 0.7,
           anchor_distance: 1,
           provenance: ["wikidata:Q944"]
         }
       ],
       [
         %Edge{
           id: 200,
           source_id: 100,
           target_id: 101,
           edge_type: :generalizes,
           confidence: 0.9
         }
       ]}
    end
  end

  defp mock_llm_http(response \\ @llm_response) do
    fn _url, _body, _headers ->
      {:ok, %{status: 200, body: response}}
    end
  end

  defp base_context do
    %{
      target_title: "Quantum Entanglement",
      subgraph_nodes: [
        %Node{
          id: 100,
          title: "Quantum Mechanics",
          node_type: :anchor,
          confidence: 1.0,
          anchor_distance: 0,
          provenance: ["wikidata:Q944"]
        }
      ],
      subgraph_edges: [],
      gap_type: :structural_hole
    }
  end

  describe "generate/2" do
    test "produces a full generation result from subgraph context" do
      assert {:ok, result} =
               Pipeline.generate(base_context(),
                 graph_repo: MockGraphRepo,
                 llm_opts: [api_key: "test-key", http_client: mock_llm_http()]
               )

      assert result.node.title == "Quantum Entanglement"
      assert result.node.node_type == :generated
      assert is_integer(result.node.id)
    end

    test "includes claims with confidence scores" do
      assert {:ok, result} =
               Pipeline.generate(base_context(),
                 graph_repo: MockGraphRepo,
                 llm_opts: [api_key: "test-key", http_client: mock_llm_http()]
               )

      assert length(result.claims) == 2
      assert hd(result.claims).confidence == 0.9
    end

    test "creates edges to existing nodes found by title" do
      assert {:ok, result} =
               Pipeline.generate(base_context(),
                 graph_repo: MockGraphRepo,
                 llm_opts: [api_key: "test-key", http_client: mock_llm_http()]
               )

      # "Quantum Mechanics" exists in MockGraphRepo, so edge should be created
      assert length(result.extracted_edges) == 1
      assert hd(result.extracted_edges).target_title == "Quantum Mechanics"
    end

    test "flags contradictions" do
      assert {:ok, result} =
               Pipeline.generate(base_context(),
                 graph_repo: MockGraphRepo,
                 llm_opts: [api_key: "test-key", http_client: mock_llm_http()]
               )

      assert length(result.contradictions) == 1
      assert hd(result.contradictions).existing_node_title == "Local Realism"
    end

    test "tracks token usage and cost" do
      assert {:ok, result} =
               Pipeline.generate(base_context(),
                 graph_repo: MockGraphRepo,
                 llm_opts: [api_key: "test-key", http_client: mock_llm_http()]
               )

      assert result.token_usage.input == 800
      assert result.token_usage.output == 400
      assert result.estimated_cost > 0.0
    end

    test "sets provenance from anchor sources in context" do
      assert {:ok, result} =
               Pipeline.generate(base_context(),
                 graph_repo: MockGraphRepo,
                 llm_opts: [api_key: "test-key", http_client: mock_llm_http()]
               )

      assert "wikidata:Q944" in result.node.provenance
    end

    test "computes anchor_distance as min(context) + 1" do
      assert {:ok, result} =
               Pipeline.generate(base_context(),
                 graph_repo: MockGraphRepo,
                 llm_opts: [api_key: "test-key", http_client: mock_llm_http()]
               )

      # Context has one node with anchor_distance=0, so generated is 1
      assert result.node.anchor_distance == 1
    end

    test "returns error on LLM failure" do
      failing_http = fn _url, _body, _headers -> {:error, :timeout} end

      assert {:error, :timeout} =
               Pipeline.generate(base_context(),
                 graph_repo: MockGraphRepo,
                 llm_opts: [api_key: "test-key", http_client: failing_http]
               )
    end
  end

  describe "generate_from_graph/3" do
    test "fetches subgraph context and generates" do
      assert {:ok, result} =
               Pipeline.generate_from_graph("Quantum Entanglement", 100,
                 graph_repo: MockGraphRepo,
                 llm_opts: [api_key: "test-key", http_client: mock_llm_http()]
               )

      assert result.node.title == "Quantum Entanglement"
      # Context from MockGraphRepo.subgraph has anchor at distance 0, so generated is 1
      assert result.node.anchor_distance == 1
    end
  end
end
