defmodule Palimpedia.Graph.Neo4jRepository do
  @moduledoc """
  Neo4j implementation of the graph repository.
  Uses Bolt.Sips for connection management.
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
    RETURN n, elementId(n) AS id
    """

    params = %{
      title: node.title,
      content: node.content,
      node_type: Atom.to_string(node.node_type),
      confidence: node.confidence,
      provenance: node.provenance,
      anchor_distance: node.anchor_distance,
      generated_at: node.generated_at && DateTime.to_iso8601(node.generated_at)
    }

    case Bolt.Sips.query(Bolt.Sips.conn(), query, params) do
      {:ok, response} ->
        [row] = response.results
        {:ok, %{node | id: row["id"]}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_node(node_id) do
    query = """
    MATCH (n:Document)
    WHERE elementId(n) = $id
    RETURN n, elementId(n) AS id
    """

    case Bolt.Sips.query(Bolt.Sips.conn(), query, %{id: node_id}) do
      {:ok, %{results: [row]}} -> {:ok, row_to_node(row)}
      {:ok, %{results: []}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def insert_edge(%Edge{} = edge) do
    edge_label = edge.edge_type |> Atom.to_string() |> String.upcase()

    query = """
    MATCH (a:Document), (b:Document)
    WHERE elementId(a) = $source_id AND elementId(b) = $target_id
    CREATE (a)-[r:#{edge_label} {
      confidence: $confidence,
      provenance: $provenance
    }]->(b)
    RETURN elementId(r) AS id
    """

    params = %{
      source_id: edge.source_id,
      target_id: edge.target_id,
      confidence: edge.confidence,
      provenance: edge.provenance
    }

    case Bolt.Sips.query(Bolt.Sips.conn(), query, params) do
      {:ok, %{results: [row]}} -> {:ok, %{edge | id: row["id"]}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def subgraph(node_id, hops \\ 2) do
    query = """
    MATCH path = (start:Document)-[*1..#{hops}]-(neighbor:Document)
    WHERE elementId(start) = $id
    RETURN nodes(path) AS nodes, relationships(path) AS rels
    """

    case Bolt.Sips.query(Bolt.Sips.conn(), query, %{id: node_id}) do
      {:ok, response} ->
        {nodes, edges} = extract_subgraph(response.results)
        {:ok, nodes, edges}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def search_nodes(query_text, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    query = """
    MATCH (n:Document)
    WHERE n.title CONTAINS $query
    RETURN n, elementId(n) AS id
    LIMIT $limit
    """

    case Bolt.Sips.query(Bolt.Sips.conn(), query, %{query: query_text, limit: limit}) do
      {:ok, response} -> {:ok, Enum.map(response.results, &row_to_node/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def find_orphans(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    query = """
    MATCH (n:Document)
    WHERE NOT (n)--()
    RETURN n, elementId(n) AS id
    LIMIT $limit
    """

    case Bolt.Sips.query(Bolt.Sips.conn(), query, %{limit: limit}) do
      {:ok, response} -> {:ok, Enum.map(response.results, &row_to_node/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp row_to_node(%{"n" => props, "id" => node_id}) do
    %Node{
      id: node_id,
      title: props["title"],
      content: props["content"],
      node_type: String.to_existing_atom(props["node_type"]),
      confidence: props["confidence"],
      provenance: props["provenance"] || [],
      anchor_distance: props["anchor_distance"]
    }
  end

  defp extract_subgraph(rows) do
    nodes =
      rows
      |> Enum.flat_map(& &1["nodes"])
      |> Enum.uniq_by(& &1.id)

    edges =
      rows
      |> Enum.flat_map(& &1["rels"])
      |> Enum.uniq_by(& &1.id)

    {nodes, edges}
  end
end
