defmodule PalimpediaWeb.ExplorerController do
  use PalimpediaWeb, :controller

  alias Palimpedia.Confidence.Scorer

  @moduledoc """
  Minimal HTML graph explorer. Browse nodes via hyperlinks,
  search by title, view subgraph neighborhoods.
  """

  @doc "GET / — Home page with search and graph stats."
  def index(conn, params) do
    query = Map.get(params, "q", "")

    search_results =
      if query != "" do
        case graph_repo().search_nodes(query, limit: 30) do
          {:ok, nodes} -> nodes
          _ -> []
        end
      else
        []
      end

    stats =
      case graph_repo().stats() do
        {:ok, s} -> s
        _ -> %{total_nodes: "?", total_edges: "?", anchor_nodes: "?", generated_nodes: "?"}
      end

    html(conn, render_index(query, search_results, stats))
  end

  @doc "GET /explore/nodes/:id — Single node view with linked neighbors."
  def show_node(conn, %{"id" => id_str}) do
    case Integer.parse(id_str) do
      {node_id, ""} ->
        with {:ok, node} <- graph_repo().get_node(node_id),
             {:ok, neighbors, edges} <- graph_repo().subgraph(node_id, 1) do
          html(conn, render_node(node, neighbors, edges))
        else
          {:error, :not_found} ->
            conn |> put_status(404) |> html(render_not_found(node_id))

          _ ->
            conn |> put_status(500) |> html(render_error("Failed to load node"))
        end

      _ ->
        conn |> put_status(400) |> html(render_error("Invalid node ID"))
    end
  end

  @doc "GET /explore/random — Redirect to a random node."
  def random(conn, _params) do
    case graph_repo().search_nodes("", limit: 50) do
      {:ok, [_ | _] = nodes} ->
        node = Enum.random(nodes)
        redirect(conn, to: "/explore/nodes/#{node.id}")

      _ ->
        redirect(conn, to: "/explore")
    end
  end

  # --- HTML Rendering ---

  defp render_index(query, results, stats) do
    results_html =
      if results == [] and query != "" do
        ~s(<p class="empty">No results for "#{esc(query)}"</p>)
      else
        results
        |> Enum.map(fn node -> result_card(node) end)
        |> Enum.join("\n")
      end

    page_layout(
      "Palimpedia Explorer",
      """
      <div class="hero">
        <h1>Palimpedia</h1>
        <p class="tagline">A Generative Epistemic Network</p>
        <form action="/explore" method="get" class="search-form">
          <input type="text" name="q" value="#{esc(query)}" placeholder="Search the knowledge graph..." autofocus />
          <button type="submit">Search</button>
        </form>
        <p class="stats">
          #{stats.total_nodes} nodes &middot;
          #{stats.total_edges} edges &middot;
          #{stats.anchor_nodes} anchors &middot;
          #{stats.generated_nodes} generated
          &middot; <a href="/explore/random">Random node</a>
        </p>
      </div>
      <div class="results">
        #{results_html}
      </div>
      """
    )
  end

  defp render_node(node, neighbors, edges) do
    other_neighbors = Enum.reject(neighbors, &(&1.id == node.id))

    outgoing = Enum.filter(edges, &(&1.source_id == node.id))
    incoming = Enum.filter(edges, &(&1.target_id == node.id))

    outgoing_html = render_edge_list(outgoing, neighbors, :outgoing)
    incoming_html = render_edge_list(incoming, neighbors, :incoming)

    regrounding_badge =
      if Scorer.requires_regrounding?(node.anchor_distance) do
        ~s[<span class="badge regrounding">Requires Regrounding</span>]
      else
        ""
      end

    content_section =
      if node.content && node.content != "" do
        ~s[<section class="content"><p>#{esc(node.content)}</p></section>]
      else
        ""
      end

    provenance_section =
      if node.provenance != [] do
        items =
          node.provenance |> Enum.map(fn p -> "<code>#{esc(p)}</code>" end) |> Enum.join(", ")

        ~s[<section class="provenance"><h3>Provenance</h3><p>#{items}</p></section>]
      else
        ""
      end

    generated_section =
      if node.generated_at do
        ts = DateTime.to_iso8601(node.generated_at)
        ~s[<section class="generated-at"><h3>Generated</h3><p>#{ts}</p></section>]
      else
        ""
      end

    outgoing_section =
      if outgoing != [] do
        count = length(outgoing)
        ~s[<section class="edges"><h3>Outgoing Edges (#{count})</h3>#{outgoing_html}</section>]
      else
        ""
      end

    incoming_section =
      if incoming != [] do
        count = length(incoming)
        ~s[<section class="edges"><h3>Incoming Edges (#{count})</h3>#{incoming_html}</section>]
      else
        ""
      end

    neighbor_section =
      if other_neighbors != [] do
        links = other_neighbors |> Enum.map(fn n -> node_link(n) end) |> Enum.join(", ")
        count = length(other_neighbors)

        ~s[<section class="neighbors"><h3>Neighborhood (#{count} nodes)</h3><p>#{links}</p></section>]
      else
        ""
      end

    confidence_str = Float.round(node.confidence * 1.0, 3)

    page_layout(
      esc(node.title),
      """
      <nav class="breadcrumb">
        <a href="/explore">Home</a> &rsaquo; <span>#{esc(node.title)}</span>
      </nav>

      <article class="node-detail">
        <header>
          <h1>#{esc(node.title)}</h1>
          <div class="meta-badges">
            <span class="badge type-#{node.node_type}">#{node.node_type}</span>
            <span class="badge confidence">confidence: #{confidence_str}</span>
            #{anchor_distance_badge(node.anchor_distance)}
            #{regrounding_badge}
          </div>
        </header>
        #{content_section}
        #{provenance_section}
        #{generated_section}
        #{outgoing_section}
        #{incoming_section}
        #{neighbor_section}
      </article>
      """
    )
  end

  defp render_edge_list(edges, all_nodes, direction) do
    node_map = Map.new(all_nodes, fn n -> {n.id, n} end)

    items =
      Enum.map(edges, fn edge ->
        linked_id = if direction == :outgoing, do: edge.target_id, else: edge.source_id
        linked_node = Map.get(node_map, linked_id)
        edge_label = edge.edge_type |> Atom.to_string() |> String.replace("_", " ")

        linked_html =
          if linked_node do
            ~s(<a href="/explore/nodes/#{linked_node.id}">#{esc(linked_node.title)}</a>)
          else
            ~s(<span class="unknown">node ##{linked_id}</span>)
          end

        arrow = if direction == :outgoing, do: "&rarr;", else: "&larr;"

        confidence_str = Float.round(edge.confidence * 1.0, 2)

        ~s[<li><span class="edge-type">#{edge_label}</span> #{arrow} #{linked_html} <span class="edge-confidence">(#{confidence_str})</span></li>]
      end)

    "<ul class=\"edge-list\">#{Enum.join(items, "\n")}</ul>"
  end

  defp render_not_found(node_id) do
    page_layout("Not Found", """
    <div class="error-page">
      <h1>Node Not Found</h1>
      <p>No node with ID #{node_id} exists in the graph.</p>
      <a href="/explore">Back to search</a>
    </div>
    """)
  end

  defp render_error(message) do
    page_layout("Error", """
    <div class="error-page">
      <h1>Error</h1>
      <p>#{esc(message)}</p>
      <a href="/explore">Back to search</a>
    </div>
    """)
  end

  # --- Components ---

  defp result_card(node) do
    type_class = "type-#{node.node_type}"
    snippet = if node.content, do: String.slice(node.content, 0, 200), else: ""
    snippet = if String.length(snippet) == 200, do: snippet <> "...", else: snippet

    """
    <a href="/explore/nodes/#{node.id}" class="result-card">
      <div class="card-header">
        <span class="card-title">#{esc(node.title)}</span>
        <span class="badge #{type_class}">#{node.node_type}</span>
      </div>
      <p class="card-snippet">#{esc(snippet)}</p>
      <div class="card-meta">
        confidence: #{Float.round(node.confidence * 1.0, 3)}
        #{anchor_distance_badge(node.anchor_distance)}
      </div>
    </a>
    """
  end

  defp node_link(node) do
    ~s(<a href="/explore/nodes/#{node.id}" class="node-link">#{esc(node.title)}</a>)
  end

  defp anchor_distance_badge(nil), do: ~s(<span class="badge distance">ungrounded</span>)

  defp anchor_distance_badge(distance) do
    ~s(<span class="badge distance">#{distance} hops from anchor</span>)
  end

  defp esc(nil), do: ""

  defp esc(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp esc(other), do: esc(to_string(other))

  # --- Layout ---

  defp page_layout(title, body) when is_binary(title) and is_binary(body) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>#{esc(title)}</title>
      <style>#{css()}</style>
    </head>
    <body>
      #{body}
    </body>
    </html>
    """
  end

  defp css do
    """
    :root {
      --ink: #0f0e0b;
      --paper: #f4f0e8;
      --rule: #c8c0a8;
      --amber: #c47c2b;
      --muted: #6b6558;
      --block: #1a1815;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: var(--paper);
      color: var(--ink);
      font-family: 'Georgia', serif;
      line-height: 1.6;
      max-width: 800px;
      margin: 0 auto;
      padding: 2rem 1.5rem;
    }
    a { color: var(--amber); text-decoration: none; }
    a:hover { text-decoration: underline; }

    /* Hero / Search */
    .hero { text-align: center; margin-bottom: 2rem; padding: 2rem 0; }
    .hero h1 {
      font-size: 2.5rem;
      letter-spacing: -0.02em;
      margin-bottom: 0.25rem;
    }
    .tagline { color: var(--muted); font-size: 0.9rem; margin-bottom: 1.5rem; }
    .search-form { display: flex; gap: 0.5rem; max-width: 500px; margin: 0 auto 1rem; }
    .search-form input {
      flex: 1;
      padding: 0.6rem 1rem;
      border: 1px solid var(--rule);
      background: white;
      font-size: 1rem;
      font-family: inherit;
    }
    .search-form button {
      padding: 0.6rem 1.2rem;
      background: var(--block);
      color: var(--paper);
      border: none;
      cursor: pointer;
      font-family: monospace;
      font-size: 0.85rem;
      letter-spacing: 0.05em;
    }
    .stats { font-size: 0.8rem; color: var(--muted); font-family: monospace; }

    /* Results */
    .results { display: flex; flex-direction: column; gap: 0.75rem; }
    .result-card {
      display: block;
      padding: 1rem 1.25rem;
      border: 1px solid var(--rule);
      background: white;
      color: var(--ink);
      transition: border-color 0.15s;
    }
    .result-card:hover { border-color: var(--amber); text-decoration: none; }
    .card-header { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 0.3rem; }
    .card-title { font-weight: bold; font-size: 1.05rem; }
    .card-snippet { font-size: 0.85rem; color: var(--muted); margin-bottom: 0.4rem; }
    .card-meta { font-size: 0.75rem; color: var(--muted); font-family: monospace; }
    .empty { color: var(--muted); text-align: center; padding: 2rem; }

    /* Badges */
    .badge {
      display: inline-block;
      font-family: monospace;
      font-size: 0.65rem;
      padding: 0.15rem 0.5rem;
      letter-spacing: 0.05em;
      text-transform: uppercase;
    }
    .type-anchor { background: rgba(196,124,43,0.15); color: var(--amber); }
    .type-generated { background: rgba(90,90,180,0.12); color: #4a4a8a; }
    .type-requested { background: rgba(100,100,100,0.1); color: var(--muted); }
    .type-bridge { background: rgba(40,140,80,0.12); color: #1a6b3a; }
    .confidence { background: rgba(0,0,0,0.05); color: var(--muted); }
    .distance { background: rgba(0,0,0,0.05); color: var(--muted); }
    .regrounding { background: rgba(139,32,32,0.12); color: #8b2020; }

    /* Breadcrumb */
    .breadcrumb { font-size: 0.8rem; color: var(--muted); margin-bottom: 1.5rem; }

    /* Node detail */
    .node-detail header { margin-bottom: 1.5rem; }
    .node-detail h1 { font-size: 1.8rem; margin-bottom: 0.5rem; }
    .meta-badges { display: flex; gap: 0.4rem; flex-wrap: wrap; }
    .node-detail section { margin-bottom: 1.5rem; }
    .node-detail h3 {
      font-family: monospace;
      font-size: 0.7rem;
      letter-spacing: 0.15em;
      text-transform: uppercase;
      color: var(--amber);
      margin-bottom: 0.5rem;
      border-bottom: 1px solid var(--rule);
      padding-bottom: 0.3rem;
    }
    .content p { white-space: pre-wrap; }
    .provenance code { background: rgba(0,0,0,0.04); padding: 0.1rem 0.3rem; font-size: 0.85rem; }

    /* Edge list */
    .edge-list { list-style: none; }
    .edge-list li {
      padding: 0.4rem 0;
      border-bottom: 1px solid rgba(200,192,168,0.3);
      font-size: 0.9rem;
    }
    .edge-type {
      font-family: monospace;
      font-size: 0.75rem;
      color: var(--amber);
      text-transform: uppercase;
    }
    .edge-confidence { font-size: 0.75rem; color: var(--muted); }
    .node-link { font-weight: 500; }
    .unknown { color: var(--muted); font-style: italic; }

    /* Error */
    .error-page { text-align: center; padding: 3rem 0; }
    .error-page h1 { margin-bottom: 1rem; }
    .error-page a { display: inline-block; margin-top: 1rem; }
    """
  end

  defp graph_repo do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
