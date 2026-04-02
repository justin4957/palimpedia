defmodule PalimpediaWeb.GraphQL.Schema do
  @moduledoc """
  Absinthe GraphQL schema for the Palimpedia knowledge graph.

  Provides researcher access to the full graph structure:
  nodes, edges, subgraphs, gaps, contradictions, and queue status.
  """

  use Absinthe.Schema

  import_types(PalimpediaWeb.GraphQL.Types)

  alias PalimpediaWeb.GraphQL.Resolvers

  query do
    @desc "Fetch a single node by ID"
    field :node, :node do
      arg(:id, non_null(:integer))
      resolve(&Resolvers.get_node/3)
    end

    @desc "Search nodes by title, with optional filters"
    field :nodes, list_of(:node) do
      arg(:query, non_null(:string))
      arg(:limit, :integer, default_value: 20)
      arg(:node_type, :string)
      arg(:min_confidence, :float)
      arg(:max_anchor_distance, :integer)
      resolve(&Resolvers.search_nodes/3)
    end

    @desc "Fetch a subgraph neighborhood around a node"
    field :subgraph, :subgraph do
      arg(:node_id, non_null(:integer))
      arg(:hops, :integer, default_value: 2)
      resolve(&Resolvers.get_subgraph/3)
    end

    @desc "Graph-level statistics"
    field :stats, :graph_stats do
      resolve(&Resolvers.get_stats/3)
    end

    @desc "Detected structural gaps, optionally filtered by type"
    field :gaps, list_of(:gap) do
      arg(:gap_type, :string)
      arg(:limit, :integer, default_value: 50)
      resolve(&Resolvers.get_gaps/3)
    end

    @desc "Open contradictions, optionally filtered by node ID"
    field :contradictions, list_of(:contradiction) do
      arg(:node_id, :integer)
      resolve(&Resolvers.get_contradictions/3)
    end

    @desc "Current generation queue entries"
    field :generation_queue, list_of(:queue_entry) do
      resolve(&Resolvers.get_queue_status/3)
    end
  end
end
