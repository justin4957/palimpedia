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
  @callback get_node(integer()) :: {:ok, Node.t()} | {:error, :not_found}

  @doc "Inserts a typed edge between two nodes."
  @callback insert_edge(Edge.t()) :: {:ok, Edge.t()} | {:error, term()}

  @doc "Returns the local subgraph neighborhood within N hops of a node."
  @callback subgraph(integer(), non_neg_integer()) ::
              {:ok, [Node.t()], [Edge.t()]} | {:error, term()}

  @doc "Finds nodes matching a search query."
  @callback search_nodes(String.t(), keyword()) :: {:ok, [Node.t()]} | {:error, term()}

  @doc "Returns nodes with no outgoing edges (orphans)."
  @callback find_orphans(keyword()) :: {:ok, [Node.t()]} | {:error, term()}

  @doc "Updates the confidence score and anchor_distance for a node."
  @callback update_confidence(integer(), float(), non_neg_integer() | nil) ::
              {:ok, Node.t()} | {:error, term()}

  @doc "Returns all anchor nodes reachable within N hops from a given node."
  @callback anchor_sources(integer(), non_neg_integer()) ::
              {:ok, [Node.t()]} | {:error, term()}

  @doc "Returns nodes whose anchor_distance exceeds the given threshold."
  @callback find_ungrounded(non_neg_integer(), keyword()) ::
              {:ok, [Node.t()]} | {:error, term()}

  @doc "Returns the shortest path length from a node to any anchor node. nil if unreachable."
  @callback shortest_anchor_distance(integer(), non_neg_integer()) ::
              {:ok, non_neg_integer() | nil} | {:error, term()}

  @doc "Returns nodes with fewer than `min_edges` connections."
  @callback find_low_connectivity(min_edges :: non_neg_integer(), keyword()) ::
              {:ok, [%{node: Node.t(), degree: non_neg_integer()}]} | {:error, term()}

  @doc """
  Returns pairs of dense node clusters that lack a direct connecting edge.
  Each result contains two node IDs that are within `max_hops` of each other
  via intermediate nodes but share no direct edge.
  """
  @callback find_structural_holes(max_hops :: non_neg_integer(), keyword()) ::
              {:ok, [map()]} | {:error, term()}

  @doc "Returns the degree (edge count) for each node type, for coverage analysis."
  @callback coverage_by_type() :: {:ok, map()} | {:error, term()}

  @doc "Returns graph-level statistics: counts by node type, edge count, etc."
  @callback stats() :: {:ok, map()} | {:error, term()}

  @doc "Deletes all nodes and relationships. Use only in tests."
  @callback delete_all() :: :ok | {:error, term()}
end
