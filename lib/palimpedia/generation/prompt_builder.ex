defmodule Palimpedia.Generation.PromptBuilder do
  @moduledoc """
  Constructs LLM prompts from subgraph context.

  The fundamental inversion: the prompt is the local graph neighborhood,
  not a topic string. This ensures generated content is structurally grounded.
  """

  alias Palimpedia.Graph.Node

  @doc """
  Builds a generation prompt from a subgraph neighborhood.
  Includes node summaries, edge relationships, and anchor provenance.
  """
  def build(target_title, context_nodes, context_edges, opts \\ []) do
    anchor_nodes = Enum.filter(context_nodes, &(&1.node_type == :anchor))
    generated_nodes = Enum.filter(context_nodes, &(&1.node_type != :anchor))

    %{
      system: system_prompt(opts),
      context: %{
        target: target_title,
        anchor_sources: format_anchors(anchor_nodes),
        related_documents: format_nodes(generated_nodes),
        relationships: format_edges(context_edges),
        gap_type: Keyword.get(opts, :gap_type, :structural_hole)
      },
      instructions: generation_instructions(target_title, opts)
    }
  end

  defp system_prompt(_opts) do
    """
    You are a knowledge synthesis engine for Palimpedia, a generative epistemic network.
    Your task is to generate a document that bridges a structural gap in the knowledge graph.

    Rules:
    - Every claim must trace to an anchor source or be marked as inferred.
    - Assign a confidence score (0.0-1.0) to each claim.
    - Identify relationships to existing nodes using typed edges.
    - Flag contradictions with existing documents explicitly.
    - Do not fabricate sources. If no anchor supports a claim, say so.
    """
  end

  defp generation_instructions(target_title, _opts) do
    """
    Generate a comprehensive document titled "#{target_title}".

    Structure your response as JSON with:
    - "title": the document title
    - "content": the document body (markdown)
    - "claims": array of {text, confidence, provenance}
    - "edges": array of {target_title, edge_type, confidence}
    - "contradictions": array of {existing_node_title, description}
    """
  end

  defp format_anchors(nodes) do
    Enum.map(nodes, fn node ->
      %{title: node.title, provenance: node.provenance, confidence: node.confidence}
    end)
  end

  defp format_nodes(nodes) do
    Enum.map(nodes, fn node ->
      %{title: node.title, confidence: node.confidence, node_type: node.node_type}
    end)
  end

  defp format_edges(edges) do
    Enum.map(edges, fn edge ->
      %{source: edge.source_id, target: edge.target_id, type: edge.edge_type}
    end)
  end
end
