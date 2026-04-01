defmodule Palimpedia.Generation.Pipeline do
  @moduledoc """
  Layer 3: Document generation pipeline.

  Orchestrates: subgraph context → prompt construction → LLM generation →
  response parsing → graph re-ingestion.

  Each document is generated with full subgraph context. The prompt is the
  local graph neighborhood, not a topic string. Outputs include confidence
  scores and provenance chains.
  """

  alias Palimpedia.Generation.{PromptBuilder, LlmClient, ResponseParser}
  alias Palimpedia.Graph.{Node, Edge}

  require Logger

  @type generation_context :: %{
          target_title: String.t(),
          subgraph_nodes: [Node.t()],
          subgraph_edges: [Edge.t()],
          gap_type: atom()
        }

  @type generation_result :: %{
          node: Node.t(),
          claims: [ResponseParser.claim()],
          extracted_edges: [ResponseParser.edge_assertion()],
          contradictions: [ResponseParser.contradiction()],
          token_usage: %{input: non_neg_integer(), output: non_neg_integer()},
          estimated_cost: float()
        }

  @doc """
  Generates a document from a subgraph context and ingests it into the graph.

  1. Builds a prompt from the local graph neighborhood
  2. Sends to the LLM (Claude)
  3. Parses the structured JSON response
  4. Creates a new graph node for the document
  5. Creates edges to related nodes found by title matching
  6. Returns the full generation result

  ## Options
    * `:graph_repo` - Graph repository module (default: configured)
    * `:llm_opts` - Options passed through to LlmClient.generate/2
    * `:context_hops` - Hops for subgraph context if fetching from graph (default: 2)
  """
  def generate(context, opts \\ []) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())
    llm_opts = Keyword.get(opts, :llm_opts, [])

    prompt_data =
      PromptBuilder.build(
        context.target_title,
        context.subgraph_nodes,
        context.subgraph_edges,
        gap_type: context.gap_type
      )

    user_prompt = Jason.encode!(prompt_data.context) <> "\n\n" <> prompt_data.instructions
    full_llm_opts = Keyword.merge(llm_opts, system: prompt_data.system)

    with {:ok, completion} <- LlmClient.generate(user_prompt, full_llm_opts),
         {:ok, parsed} <- ResponseParser.parse(completion.content) do
      token_usage = %{input: completion.input_tokens, output: completion.output_tokens}
      estimated_cost = LlmClient.estimate_cost(completion)

      provenance =
        context.subgraph_nodes
        |> Enum.filter(&(&1.node_type == :anchor))
        |> Enum.flat_map(& &1.provenance)
        |> Enum.uniq()

      anchor_distance = compute_anchor_distance(context.subgraph_nodes)

      new_node =
        Node.new_generated(
          parsed.title,
          parsed.content,
          confidence: compute_generation_confidence(parsed.claims),
          provenance: provenance,
          anchor_distance: anchor_distance
        )

      case graph_repo.insert_node(new_node) do
        {:ok, inserted_node} ->
          edge_results = create_edges(inserted_node, parsed.edges, graph_repo)

          Logger.info(
            "Generated document: #{parsed.title} (#{length(parsed.claims)} claims, " <>
              "#{length(edge_results)} edges, #{length(parsed.contradictions)} contradictions, " <>
              "cost: $#{Float.round(estimated_cost, 6)})"
          )

          {:ok,
           %{
             node: inserted_node,
             claims: parsed.claims,
             extracted_edges: parsed.edges,
             contradictions: parsed.contradictions,
             token_usage: token_usage,
             estimated_cost: estimated_cost
           }}

        {:error, reason} ->
          {:error, {:node_insert_failed, reason}}
      end
    end
  end

  @doc """
  Generates a document for a target title using the graph neighborhood as context.

  Fetches the subgraph around existing nodes matching the target title,
  or uses the full graph neighborhood if a center_node_id is provided.
  """
  def generate_from_graph(target_title, center_node_id, opts \\ []) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())
    hops = Keyword.get(opts, :context_hops, 2)

    case graph_repo.subgraph(center_node_id, hops) do
      {:ok, nodes, edges} ->
        context = %{
          target_title: target_title,
          subgraph_nodes: nodes,
          subgraph_edges: edges,
          gap_type: Keyword.get(opts, :gap_type, :structural_hole)
        }

        generate(context, opts)

      {:error, reason} ->
        {:error, {:subgraph_fetch_failed, reason}}
    end
  end

  # --- Private ---

  defp create_edges(source_node, edge_assertions, graph_repo) do
    Enum.flat_map(edge_assertions, fn assertion ->
      case graph_repo.search_nodes(assertion.target_title, limit: 1) do
        {:ok, [target | _]} ->
          edge = %Edge{
            source_id: source_node.id,
            target_id: target.id,
            edge_type: assertion.edge_type,
            confidence: assertion.confidence,
            provenance: source_node.provenance
          }

          case graph_repo.insert_edge(edge) do
            {:ok, inserted} -> [inserted]
            {:error, _} -> []
          end

        _ ->
          []
      end
    end)
  end

  defp compute_generation_confidence(claims) do
    if claims == [] do
      0.0
    else
      claims
      |> Enum.map(& &1.confidence)
      |> Enum.sum()
      |> Kernel./(length(claims))
    end
  end

  defp compute_anchor_distance(subgraph_nodes) do
    anchor_distances =
      subgraph_nodes
      |> Enum.map(& &1.anchor_distance)
      |> Enum.reject(&is_nil/1)

    case anchor_distances do
      [] -> nil
      distances -> Enum.min(distances) + 1
    end
  end

  defp graph_repository do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
