defmodule Palimpedia.Anchor.Ingestion do
  @moduledoc """
  Pipeline for ingesting anchor corpus data from external sources.

  Handles entity extraction, relationship tagging, and node creation
  from verified external sources (Wikidata, arXiv, legal databases, etc.).
  """

  alias Palimpedia.Anchor.Source
  alias Palimpedia.Graph.{Node, Edge}

  @type ingestion_result :: %{
          nodes_created: non_neg_integer(),
          edges_created: non_neg_integer(),
          errors: [term()]
        }

  @doc """
  Ingests data from an anchor source into the graph.
  Returns a summary of nodes and edges created.
  """
  @callback ingest(Source.t(), keyword()) :: {:ok, ingestion_result()} | {:error, term()}

  @doc """
  Extracts entities and relationships from raw source data.
  Returns nodes and edges ready for graph insertion.
  """
  @callback extract(Source.t(), term()) :: {:ok, [Node.t()], [Edge.t()]} | {:error, term()}
end
