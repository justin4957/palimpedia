defmodule Palimpedia.Graph.Repository do
  @moduledoc """
  Interface to the Neo4j graph database.

  All graph reads and writes go through this module. The graph substrate
  is the single source of truth — everything else is interface.
  """

  alias Palimpedia.Graph.{Node, Edge}

  @doc "Inserts a node into the graph and returns it with its assigned ID."
  @callback insert_node(Node.t()) :: {:ok, Node.t()} | {:error, term()}

  @doc "Retrieves a node by ID."
  @callback get_node(String.t()) :: {:ok, Node.t()} | {:error, :not_found}

  @doc "Inserts a typed edge between two nodes."
  @callback insert_edge(Edge.t()) :: {:ok, Edge.t()} | {:error, term()}

  @doc "Returns the local subgraph neighborhood within N hops of a node."
  @callback subgraph(String.t(), non_neg_integer()) ::
              {:ok, [Node.t()], [Edge.t()]} | {:error, term()}

  @doc "Finds nodes matching a search query."
  @callback search_nodes(String.t(), keyword()) :: {:ok, [Node.t()]} | {:error, term()}

  @doc "Returns nodes with no outgoing edges (orphans)."
  @callback find_orphans(keyword()) :: {:ok, [Node.t()]} | {:error, term()}
end
