defmodule Palimpedia.Anchor.Adapter do
  @moduledoc """
  Behaviour for anchor corpus source adapters.

  Each external data source (Wikidata, arXiv, etc.) implements this behaviour
  to provide a uniform interface for fetching and extracting entities.
  """

  alias Palimpedia.Graph.{Node, Edge}

  @type entity :: %{
          title: String.t(),
          content: String.t(),
          source_id: String.t(),
          properties: map()
        }

  @type relationship :: %{
          source_id: String.t(),
          target_id: String.t(),
          edge_type: Edge.edge_type(),
          confidence: float()
        }

  @type fetch_result :: %{
          entities: [entity()],
          relationships: [relationship()]
        }

  @doc "Fetches a single entity by its source-specific identifier."
  @callback fetch_entity(identifier :: String.t(), opts :: keyword()) ::
              {:ok, fetch_result()} | {:error, term()}

  @doc "Fetches multiple entities by a list of identifiers."
  @callback fetch_entities(identifiers :: [String.t()], opts :: keyword()) ::
              {:ok, fetch_result()} | {:error, term()}

  @doc "Searches for entities matching a query string."
  @callback search(query :: String.t(), opts :: keyword()) ::
              {:ok, fetch_result()} | {:error, term()}

  @doc """
  Converts raw adapter entities into Palimpedia graph nodes.
  All returned nodes are anchor type with confidence 1.0.
  """
  def entities_to_nodes(entities) do
    Enum.map(entities, fn entity ->
      Node.new_anchor(entity.title, entity.content, entity.source_id)
    end)
  end
end
