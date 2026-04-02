defmodule PalimpediaWeb.GraphQL.Resolvers do
  @moduledoc "Absinthe resolvers for the Palimpedia knowledge graph."

  alias Palimpedia.Confidence.{Scorer, Contradiction}
  alias Palimpedia.GapDetection.{Analyzer, GenerationQueue}

  def get_node(_parent, %{id: node_id}, _resolution) do
    case graph_repo().get_node(node_id) do
      {:ok, node} -> {:ok, format_node(node)}
      {:error, :not_found} -> {:error, "Node not found"}
    end
  end

  def search_nodes(_parent, args, _resolution) do
    query = Map.get(args, :query, "")
    limit = Map.get(args, :limit, 20)
    node_type = Map.get(args, :node_type)
    min_confidence = Map.get(args, :min_confidence)
    max_anchor_distance = Map.get(args, :max_anchor_distance)

    case graph_repo().search_nodes(query, limit: limit) do
      {:ok, nodes} ->
        filtered =
          nodes
          |> maybe_filter_type(node_type)
          |> maybe_filter_confidence(min_confidence)
          |> maybe_filter_distance(max_anchor_distance)

        {:ok, Enum.map(filtered, &format_node/1)}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  def get_subgraph(_parent, %{node_id: node_id} = args, _resolution) do
    hops = Map.get(args, :hops, 2) |> min(5)

    case graph_repo().subgraph(node_id, hops) do
      {:ok, nodes, edges} ->
        {:ok,
         %{
           nodes: Enum.map(nodes, &format_node/1),
           edges: Enum.map(edges, &format_edge/1),
           center_node_id: node_id,
           hops: hops
         }}

      {:error, :not_found} ->
        {:error, "Node not found"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  def get_stats(_parent, _args, _resolution) do
    case graph_repo().stats() do
      {:ok, stats} -> {:ok, stats}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def get_gaps(_parent, args, _resolution) do
    opts = [
      graph_repo: graph_repo(),
      limit: Map.get(args, :limit, 50)
    ]

    case Analyzer.analyze(opts) do
      {:ok, result} ->
        gaps =
          result.gaps
          |> maybe_filter_gap_type(Map.get(args, :gap_type))
          |> Enum.map(fn gap ->
            %{
              gap_type: Atom.to_string(gap.gap_type),
              priority: gap.priority,
              suggested_title: gap.suggested_title,
              context: gap.context
            }
          end)

        {:ok, gaps}
    end
  end

  def get_contradictions(_parent, args, _resolution) do
    node_id = Map.get(args, :node_id)

    case Contradiction.list_open(node_id: node_id) do
      {:ok, contradictions} ->
        {:ok,
         Enum.map(contradictions, fn c ->
           %{
             id: c.id,
             node_a_id: c.node_a_id,
             node_b_id: c.node_b_id,
             description: c.description,
             severity: Atom.to_string(c.severity),
             status: Atom.to_string(c.status),
             flagged_by: Atom.to_string(c.flagged_by),
             flagged_at: DateTime.to_iso8601(c.flagged_at)
           }
         end)}
    end
  end

  def get_queue_status(_parent, _args, _resolution) do
    entries = GenerationQueue.list_pending()

    {:ok,
     Enum.map(entries, fn e ->
       %{
         id: e.id,
         gap_type: Atom.to_string(e.gap_type),
         priority: e.priority,
         suggested_title: e.suggested_title,
         status: Atom.to_string(e.status),
         demand_count: e.demand_count,
         inserted_at: DateTime.to_iso8601(e.inserted_at)
       }
     end)}
  end

  # --- Formatting ---

  defp format_node(node) do
    %{
      id: node.id,
      title: node.title,
      content: node.content,
      node_type: Atom.to_string(node.node_type),
      confidence: %{
        score: node.confidence,
        anchor_distance: node.anchor_distance,
        requires_regrounding: Scorer.requires_regrounding?(node.anchor_distance)
      },
      provenance: node.provenance,
      generated_at: node.generated_at && DateTime.to_iso8601(node.generated_at),
      metadata: node.metadata
    }
  end

  defp format_edge(edge) do
    %{
      id: edge.id,
      source_id: edge.source_id,
      target_id: edge.target_id,
      edge_type: Atom.to_string(edge.edge_type),
      confidence: edge.confidence,
      provenance: edge.provenance
    }
  end

  # --- Filters ---

  defp maybe_filter_type(nodes, nil), do: nodes

  defp maybe_filter_type(nodes, type) do
    atom_type = String.to_existing_atom(type)
    Enum.filter(nodes, &(&1.node_type == atom_type))
  rescue
    ArgumentError -> nodes
  end

  defp maybe_filter_confidence(nodes, nil), do: nodes
  defp maybe_filter_confidence(nodes, min), do: Enum.filter(nodes, &(&1.confidence >= min))

  defp maybe_filter_distance(nodes, nil), do: nodes

  defp maybe_filter_distance(nodes, max) do
    Enum.filter(nodes, fn n -> n.anchor_distance != nil and n.anchor_distance <= max end)
  end

  defp maybe_filter_gap_type(gaps, nil), do: gaps

  defp maybe_filter_gap_type(gaps, type) do
    atom_type = String.to_existing_atom(type)
    Enum.filter(gaps, &(&1.gap_type == atom_type))
  rescue
    ArgumentError -> gaps
  end

  defp graph_repo do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
