defmodule PalimpediaWeb.NodeController do
  use PalimpediaWeb, :controller

  alias PalimpediaWeb.GraphJSON
  alias Palimpedia.Graph.{Node, Edge}
  alias Palimpedia.Confidence.Contradiction

  @moduledoc """
  REST API for graph nodes (documents).
  Supports retrieval, search, and the three tiers of user interaction.
  """

  @doc "GET /api/nodes/:id — Retrieve a document node with confidence metadata."
  def show(conn, %{"id" => node_id_str}) do
    case Integer.parse(node_id_str) do
      {node_id, ""} ->
        case graph_repo().get_node(node_id) do
          {:ok, node} ->
            contradiction_count = contradiction_count_for(node_id)

            json(conn, %{
              data: GraphJSON.node_to_json(node),
              contradictions: %{open_count: contradiction_count}
            })

          {:error, :not_found} ->
            conn |> put_status(404) |> json(%{error: "Node not found", node_id: node_id})
        end

      _ ->
        conn |> put_status(400) |> json(%{error: "Invalid node ID, must be an integer"})
    end
  end

  @doc "GET /api/nodes/search?q=query — Search nodes by title/content."
  def search(conn, params) do
    query_text = Map.get(params, "q", "")
    limit = params |> Map.get("limit", "20") |> parse_int(20)

    if query_text == "" do
      conn |> put_status(400) |> json(%{error: "Query parameter 'q' is required"})
    else
      case graph_repo().search_nodes(query_text, limit: limit) do
        {:ok, nodes} ->
          json(conn, %{
            data: GraphJSON.nodes_to_json(nodes),
            meta: %{query: query_text, count: length(nodes), limit: limit}
          })

        {:error, reason} ->
          conn |> put_status(500) |> json(%{error: "Search failed", detail: inspect(reason)})
      end
    end
  end

  @doc "POST /api/nodes/request — Tier 1: Request generation of a new document."
  def request_node(conn, %{"title" => title} = _params) do
    node = Node.new_request(title)

    case graph_repo().insert_node(node) do
      {:ok, inserted} ->
        conn
        |> put_status(201)
        |> json(%{
          data: GraphJSON.node_to_json(inserted),
          meta: %{tier: 1, status: "queued"}
        })

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "Failed to register node request", detail: inspect(reason)})
    end
  end

  def request_node(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing required field: title"})
  end

  @doc "POST /api/edges — Tier 2: Assert an edge relationship."
  def assert_edge(
        conn,
        %{"source_id" => source_str, "target_id" => target_str, "edge_type" => edge_type_str} =
          params
      ) do
    with {source_id, ""} <- Integer.parse(source_str),
         {target_id, ""} <- Integer.parse(target_str),
         {:ok, edge_type} <- parse_edge_type(edge_type_str) do
      confidence = Map.get(params, "confidence", 0.5) |> ensure_float()

      edge = %Edge{
        source_id: source_id,
        target_id: target_id,
        edge_type: edge_type,
        confidence: confidence,
        provenance: []
      }

      case graph_repo().insert_edge(edge) do
        {:ok, inserted} ->
          conn
          |> put_status(201)
          |> json(%{
            data: GraphJSON.edge_to_json(inserted),
            meta: %{tier: 2, status: "created"}
          })

        {:error, reason} ->
          conn
          |> put_status(422)
          |> json(%{error: "Failed to create edge", detail: inspect(reason)})
      end
    else
      _ ->
        conn
        |> put_status(400)
        |> json(%{
          error:
            "Invalid parameters. Required: source_id (int), target_id (int), edge_type (valid type)"
        })
    end
  end

  def assert_edge(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Required fields: source_id, target_id, edge_type"})
  end

  @doc "POST /api/contradictions — Tier 3: Flag a contradiction."
  def flag_contradiction(conn, %{
        "node_a_id" => a_str,
        "node_b_id" => b_str,
        "description" => description
      }) do
    with {node_a_id, ""} <- Integer.parse(a_str),
         {node_b_id, ""} <- Integer.parse(b_str) do
      severity = parse_severity(conn.params["severity"])

      case Contradiction.flag(node_a_id, node_b_id, description,
             severity: severity,
             flagged_by: :user
           ) do
        {:ok, contradiction} ->
          conn
          |> put_status(201)
          |> json(%{
            data: %{
              id: contradiction.id,
              tier: 3,
              node_a_id: contradiction.node_a_id,
              node_b_id: contradiction.node_b_id,
              description: contradiction.description,
              severity: contradiction.severity,
              status: contradiction.status,
              flagged_at: DateTime.to_iso8601(contradiction.flagged_at)
            },
            meta: %{status: "flagged"}
          })
      end
    else
      _ ->
        conn
        |> put_status(400)
        |> json(%{error: "Invalid node IDs, must be integers"})
    end
  end

  def flag_contradiction(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Required fields: node_a_id, node_b_id, description"})
  end

  # --- Private ---

  defp graph_repo do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp parse_int(n, _default) when is_integer(n), do: n
  defp parse_int(_, default), do: default

  defp parse_edge_type(type_string) do
    normalized = type_string |> String.downcase() |> String.trim()

    try do
      atom = String.to_existing_atom(normalized)

      if atom in Palimpedia.Graph.Edge.valid_types() do
        {:ok, atom}
      else
        :error
      end
    rescue
      ArgumentError -> :error
    end
  end

  defp ensure_float(v) when is_float(v), do: v
  defp ensure_float(v) when is_integer(v), do: v / 1
  defp ensure_float(_), do: 0.5

  defp contradiction_count_for(node_id) do
    if Process.whereis(Contradiction) do
      Contradiction.count_for_node(node_id)
    else
      0
    end
  end

  defp parse_severity("high"), do: :high
  defp parse_severity("low"), do: :low
  defp parse_severity(_), do: :medium
end
