defmodule Palimpedia.Graph.Node do
  @moduledoc """
  Represents a document node in the knowledge graph.

  Every document in Palimpedia is a node with typed edges to other nodes.
  The graph is the ground truth; documents are rendered views of relational structure.
  """

  @type confidence_score :: float()

  @type t :: %__MODULE__{
          id: String.t() | nil,
          title: String.t(),
          content: String.t() | nil,
          node_type: node_type(),
          confidence: confidence_score(),
          provenance: [String.t()],
          generated_at: DateTime.t() | nil,
          anchor_distance: non_neg_integer() | nil,
          metadata: map()
        }

  @type node_type :: :anchor | :generated | :requested | :bridge

  defstruct [
    :id,
    :title,
    :content,
    :generated_at,
    :anchor_distance,
    node_type: :generated,
    confidence: 0.0,
    provenance: [],
    metadata: %{}
  ]

  @doc """
  Creates a new anchor node from a verified external source.
  Anchor nodes have maximum confidence and zero anchor distance.
  """
  def new_anchor(title, content, source_id) do
    %__MODULE__{
      title: title,
      content: content,
      node_type: :anchor,
      confidence: 1.0,
      anchor_distance: 0,
      provenance: [source_id]
    }
  end

  @doc """
  Creates a new generated node from the generation pipeline.
  Confidence is derived from the subgraph context used in generation.
  """
  def new_generated(title, content, opts \\ []) do
    %__MODULE__{
      title: title,
      content: content,
      node_type: :generated,
      confidence: Keyword.get(opts, :confidence, 0.0),
      provenance: Keyword.get(opts, :provenance, []),
      anchor_distance: Keyword.get(opts, :anchor_distance, nil),
      generated_at: DateTime.utc_now()
    }
  end

  @doc """
  Creates a user-requested node placeholder that enters the generation queue.
  """
  def new_request(title) do
    %__MODULE__{
      title: title,
      node_type: :requested,
      confidence: 0.0,
      provenance: []
    }
  end
end
