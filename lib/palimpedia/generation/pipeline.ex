defmodule Palimpedia.Generation.Pipeline do
  @moduledoc """
  Layer 3: Document generation pipeline.

  Each document is generated with full subgraph context. The prompt is the
  local graph neighborhood, not a topic string. Outputs include confidence
  scores and provenance chains.
  """

  alias Palimpedia.Graph.Node

  @type generation_context :: %{
          target_title: String.t(),
          subgraph_nodes: [Node.t()],
          gap_type: atom(),
          anchor_sources: [String.t()]
        }

  @type generation_result :: %{
          node: Node.t(),
          extracted_edges: [map()],
          claims: [claim()],
          token_usage: non_neg_integer()
        }

  @type claim :: %{
          text: String.t(),
          confidence: float(),
          provenance: [String.t()]
        }

  @doc """
  Generates a document from a subgraph context.
  The prompt is constructed from the local graph neighborhood.
  """
  @callback generate(generation_context()) :: {:ok, generation_result()} | {:error, term()}

  @doc """
  Re-ingests a generated document back into the graph as nodes and edges.
  """
  @callback ingest_result(generation_result()) :: {:ok, Node.t()} | {:error, term()}
end
