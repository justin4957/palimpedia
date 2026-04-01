defmodule Palimpedia.Graph.Neo4jRepository do
  @moduledoc """
  Neo4j implementation of the graph repository.

  Uses Bolt.Sips for connection management. All queries use parameterized
  Cypher to prevent injection. Node and relationship IDs are Neo4j internal
  integer IDs accessed via the Bolt.Sips.Types structs.
  """

  @behaviour Palimpedia.Graph.Repository

  alias Palimpedia.Graph.{Node, Edge}

  @impl true
  def insert_node(%Node{} = node) do
    query = """
    CREATE (n:Document {
      title: $title,
      content: $content,
      node_type: $node_type,
      confidence: $confidence,
      provenance: $provenance,
      anchor_distance: $anchor_distance,
      generated_at: $generated_at
    })
    RETURN n
    """

    params = node_to_params(node)

    with {:ok, response} <- execute(query, params),
         [%{"n" => neo4j_node}] <- response.results do
      {:ok, neo4j_node_to_struct(neo4j_node)}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unexpected_response}
    end
  end

  @impl true
  def get_node(node_id) when is_integer(node_id) do
    query = """
    MATCH (n:Document)
    WHERE id(n) = $id
    RETURN n
    """

    with {:ok, response} <- execute(query, %{id: node_id}) do
      case response.results do
        [%{"n" => neo4j_node}] -> {:ok, neo4j_node_to_struct(neo4j_node)}
        [] -> {:error, :not_found}
      end
    end
  end

  @impl true
  def insert_edge(%Edge{} = edge) do
    with :ok <- validate_edge_type(edge.edge_type) do
      edge_label = edge.edge_type |> Atom.to_string() |> String.upcase()

      # Cypher doesn't allow parameterized relationship types, so we
      # interpolate the validated label. Edge types are from a fixed
      # vocabulary so this is safe from injection.
      query = """
      MATCH (a:Document), (b:Document)
      WHERE id(a) = $source_id AND id(b) = $target_id
      CREATE (a)-[r:#{edge_label} {
        confidence: $confidence,
        provenance: $provenance
      }]->(b)
      RETURN r
      """

      params = %{
        source_id: edge.source_id,
        target_id: edge.target_id,
        confidence: edge.confidence,
        provenance: edge.provenance
      }

      with {:ok, response} <- execute(query, params),
           [%{"r" => neo4j_rel}] <- response.results do
        {:ok, neo4j_rel_to_edge(neo4j_rel)}
      else
        {:ok, %{results: []}} -> {:error, :nodes_not_found}
        {:error, reason} -> {:error, reason}
        _ -> {:error, :unexpected_response}
      end
    end
  end

  @impl true
  def subgraph(node_id, hops \\ 2) when is_integer(node_id) and hops > 0 do
    query = """
    MATCH (start:Document)
    WHERE id(start) = $id
    OPTIONAL MATCH path = (start)-[*1..#{hops}]-(neighbor:Document)
    WITH start, collect(nodes(path)) AS all_node_lists, collect(relationships(path)) AS all_rel_lists
    RETURN start,
           reduce(acc = [], ns IN all_node_lists | acc + ns) AS nodes,
           reduce(acc = [], rs IN all_rel_lists | acc + rs) AS rels
    """

    with {:ok, response} <- execute(query, %{id: node_id}) do
      case response.results do
        [%{"start" => start_node, "nodes" => raw_nodes, "rels" => raw_rels}] ->
          nodes =
            [start_node | raw_nodes || []]
            |> Enum.filter(&is_struct(&1, Bolt.Sips.Types.Node))
            |> Enum.uniq_by(& &1.id)
            |> Enum.map(&neo4j_node_to_struct/1)

          edges =
            (raw_rels || [])
            |> Enum.filter(&is_struct(&1, Bolt.Sips.Types.Relationship))
            |> Enum.uniq_by(& &1.id)
            |> Enum.map(&neo4j_rel_to_edge/1)

          {:ok, nodes, edges}

        [] ->
          {:error, :not_found}
      end
    end
  end

  @impl true
  def search_nodes(query_text, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    query = """
    MATCH (n:Document)
    WHERE n.title CONTAINS $query
    RETURN n
    ORDER BY n.confidence DESC
    LIMIT $limit
    """

    with {:ok, response} <- execute(query, %{query: query_text, limit: limit}) do
      nodes =
        Enum.map(response.results, fn %{"n" => neo4j_node} -> neo4j_node_to_struct(neo4j_node) end)

      {:ok, nodes}
    end
  end

  @impl true
  def find_orphans(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    query = """
    MATCH (n:Document)
    WHERE NOT (n)--()
    RETURN n
    LIMIT $limit
    """

    with {:ok, response} <- execute(query, %{limit: limit}) do
      nodes =
        Enum.map(response.results, fn %{"n" => neo4j_node} -> neo4j_node_to_struct(neo4j_node) end)

      {:ok, nodes}
    end
  end

  @impl true
  def update_confidence(node_id, confidence, anchor_distance)
      when is_integer(node_id) and is_float(confidence) do
    query = """
    MATCH (n:Document)
    WHERE id(n) = $id
    SET n.confidence = $confidence, n.anchor_distance = $anchor_distance
    RETURN n
    """

    params = %{id: node_id, confidence: confidence, anchor_distance: anchor_distance}

    with {:ok, response} <- execute(query, params) do
      case response.results do
        [%{"n" => neo4j_node}] -> {:ok, neo4j_node_to_struct(neo4j_node)}
        [] -> {:error, :not_found}
      end
    end
  end

  @impl true
  def anchor_sources(node_id, max_hops \\ 6) when is_integer(node_id) do
    query = """
    MATCH (start:Document)
    WHERE id(start) = $id
    MATCH path = (start)-[*1..#{max_hops}]-(anchor:Document {node_type: 'anchor'})
    RETURN DISTINCT anchor
    """

    with {:ok, response} <- execute(query, %{id: node_id}) do
      nodes =
        Enum.map(response.results, fn %{"anchor" => neo4j_node} ->
          neo4j_node_to_struct(neo4j_node)
        end)

      {:ok, nodes}
    end
  end

  @impl true
  def find_ungrounded(max_distance, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    query = """
    MATCH (n:Document)
    WHERE n.anchor_distance IS NOT NULL AND n.anchor_distance > $max_distance
    RETURN n
    ORDER BY n.anchor_distance DESC
    LIMIT $limit
    """

    with {:ok, response} <- execute(query, %{max_distance: max_distance, limit: limit}) do
      nodes =
        Enum.map(response.results, fn %{"n" => neo4j_node} ->
          neo4j_node_to_struct(neo4j_node)
        end)

      {:ok, nodes}
    end
  end

  @impl true
  def shortest_anchor_distance(node_id, max_hops \\ 10) when is_integer(node_id) do
    query = """
    MATCH (start:Document)
    WHERE id(start) = $id
    OPTIONAL MATCH path = shortestPath((start)-[*1..#{max_hops}]-(anchor:Document {node_type: 'anchor'}))
    RETURN CASE WHEN path IS NULL THEN null ELSE length(path) END AS distance
    """

    with {:ok, response} <- execute(query, %{id: node_id}) do
      case response.results do
        [%{"distance" => distance}] -> {:ok, distance}
        [] -> {:ok, nil}
      end
    end
  end

  @impl true
  def delete_all do
    query = "MATCH (n) DETACH DELETE n"

    case execute(query) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Private helpers ---

  defp execute(query, params \\ %{}) do
    conn = Bolt.Sips.conn()
    Bolt.Sips.query(conn, query, params)
  end

  defp node_to_params(%Node{} = node) do
    %{
      title: node.title,
      content: node.content,
      node_type: Atom.to_string(node.node_type),
      confidence: node.confidence,
      provenance: node.provenance,
      anchor_distance: node.anchor_distance,
      generated_at: if(node.generated_at, do: DateTime.to_iso8601(node.generated_at))
    }
  end

  defp neo4j_node_to_struct(%Bolt.Sips.Types.Node{} = neo4j_node) do
    props = neo4j_node.properties

    %Node{
      id: neo4j_node.id,
      title: props["title"],
      content: props["content"],
      node_type: String.to_existing_atom(props["node_type"]),
      confidence: props["confidence"] || 0.0,
      provenance: props["provenance"] || [],
      anchor_distance: props["anchor_distance"],
      generated_at: parse_datetime(props["generated_at"])
    }
  end

  defp neo4j_rel_to_edge(%Bolt.Sips.Types.Relationship{} = rel) do
    %Edge{
      id: rel.id,
      source_id: rel.start,
      target_id: rel.end,
      edge_type: rel.type |> String.downcase() |> String.to_existing_atom(),
      confidence: (rel.properties || %{})["confidence"] || 0.0,
      provenance: (rel.properties || %{})["provenance"] || []
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp validate_edge_type(edge_type) do
    if edge_type in Edge.valid_types() do
      :ok
    else
      {:error, {:invalid_edge_type, edge_type}}
    end
  end
end
