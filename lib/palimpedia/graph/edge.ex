defmodule Palimpedia.Graph.Edge do
  @moduledoc """
  Represents a typed relationship between two nodes in the knowledge graph.

  Every concept reference, entity mention, and thematic relationship is a typed edge.
  Edges carry their own confidence and provenance, independent of their endpoint nodes.
  """

  @type edge_type ::
          :references
          | :contradicts
          | :supports
          | :derived_from
          | :related_to
          | :influences
          | :precedes
          | :specializes
          | :generalizes

  @type t :: %__MODULE__{
          id: String.t() | nil,
          source_id: String.t(),
          target_id: String.t(),
          edge_type: edge_type(),
          confidence: float(),
          provenance: [String.t()],
          metadata: map()
        }

  defstruct [
    :id,
    :source_id,
    :target_id,
    :edge_type,
    confidence: 0.0,
    provenance: [],
    metadata: %{}
  ]

  @doc "All valid edge types in the Palimpedia graph vocabulary."
  def valid_types do
    [
      :references,
      :contradicts,
      :supports,
      :derived_from,
      :related_to,
      :influences,
      :precedes,
      :specializes,
      :generalizes
    ]
  end
end
