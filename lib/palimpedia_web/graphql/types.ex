defmodule PalimpediaWeb.GraphQL.Types do
  @moduledoc "Absinthe type definitions for the Palimpedia knowledge graph."

  use Absinthe.Schema.Notation

  @desc "A document node in the knowledge graph"
  object :node do
    field(:id, non_null(:integer))
    field(:title, non_null(:string))
    field(:content, :string)
    field(:node_type, non_null(:string))
    field(:confidence, non_null(:confidence_envelope))
    field(:provenance, list_of(:string))
    field(:generated_at, :string)
    field(:metadata, :json)
  end

  @desc "Confidence envelope — every node carries this metadata"
  object :confidence_envelope do
    field(:score, non_null(:float))
    field(:anchor_distance, :integer)
    field(:requires_regrounding, non_null(:boolean))
  end

  @desc "A typed relationship between two nodes"
  object :edge do
    field(:id, non_null(:integer))
    field(:source_id, non_null(:integer))
    field(:target_id, non_null(:integer))
    field(:edge_type, non_null(:string))
    field(:confidence, non_null(:float))
    field(:provenance, list_of(:string))
  end

  @desc "A subgraph neighborhood: nodes + edges"
  object :subgraph do
    field(:nodes, non_null(list_of(:node)))
    field(:edges, non_null(list_of(:edge)))
    field(:center_node_id, non_null(:integer))
    field(:hops, non_null(:integer))
  end

  @desc "Graph-level statistics"
  object :graph_stats do
    field(:total_nodes, non_null(:integer))
    field(:total_edges, non_null(:integer))
    field(:anchor_nodes, non_null(:integer))
    field(:generated_nodes, non_null(:integer))
    field(:requested_nodes, non_null(:integer))
    field(:bridge_nodes, non_null(:integer))
    field(:avg_confidence, :float)
  end

  @desc "A detected structural gap in the graph"
  object :gap do
    field(:gap_type, non_null(:string))
    field(:priority, non_null(:float))
    field(:suggested_title, :string)
    field(:context, :json)
  end

  @desc "A contradiction between two documents"
  object :contradiction do
    field(:id, non_null(:string))
    field(:node_a_id, non_null(:integer))
    field(:node_b_id, non_null(:integer))
    field(:description, non_null(:string))
    field(:severity, non_null(:string))
    field(:status, non_null(:string))
    field(:flagged_by, non_null(:string))
    field(:flagged_at, non_null(:string))
  end

  @desc "Generation queue entry"
  object :queue_entry do
    field(:id, non_null(:string))
    field(:gap_type, non_null(:string))
    field(:priority, non_null(:float))
    field(:suggested_title, :string)
    field(:status, non_null(:string))
    field(:demand_count, non_null(:integer))
    field(:inserted_at, non_null(:string))
  end

  scalar :json, name: "JSON" do
    serialize(& &1)
    parse(fn %{value: value} -> {:ok, value} end)
  end
end
