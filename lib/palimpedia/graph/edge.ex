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
          id: integer() | nil,
          source_id: integer(),
          target_id: integer(),
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

  @base_types [
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

  @doc "All valid edge types in the base Palimpedia graph vocabulary."
  def valid_types, do: @base_types

  @doc """
  All valid edge types including domain-specific extensions.
  Pass a domain ID to include that domain's edge types.
  """
  def valid_types_for(domain_id) do
    Palimpedia.Domain.Config.edge_types_for(domain_id)
  end
end
