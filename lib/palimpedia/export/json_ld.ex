defmodule Palimpedia.Export.JsonLD do
  @moduledoc """
  Exports the knowledge graph as JSON-LD with schema.org vocabulary.
  """

  @doc "Exports nodes and edges as a JSON-LD document."
  def export(nodes, edges) do
    graph_items = Enum.map(nodes, &node_to_jsonld(&1, edges))

    document = %{
      "@context" => %{
        "@vocab" => "http://schema.org/",
        "palimpedia" => "https://palimpedia.org/ontology/",
        "confidence" => "palimpedia:confidence",
        "nodeType" => "palimpedia:nodeType",
        "anchorDistance" => "palimpedia:anchorDistance"
      },
      "@graph" => graph_items
    }

    Jason.encode!(document, pretty: true)
  end

  @doc "Exports a single node as a JSON-LD object."
  def node_to_jsonld(node, edges \\ []) do
    outgoing = Enum.filter(edges, &(&1.source_id == node.id))

    item = %{
      "@id" => "https://palimpedia.org/resource/node/#{node.id}",
      "@type" => "Article",
      "name" => node.title,
      "nodeType" => Atom.to_string(node.node_type),
      "confidence" => node.confidence,
      "identifier" => node.provenance || []
    }

    item = if node.content, do: Map.put(item, "description", node.content), else: item

    item =
      if node.anchor_distance,
        do: Map.put(item, "anchorDistance", node.anchor_distance),
        else: item

    item =
      if node.generated_at do
        Map.put(item, "dateCreated", DateTime.to_iso8601(node.generated_at))
      else
        item
      end

    item =
      if outgoing != [] do
        relationships =
          Enum.map(outgoing, fn edge ->
            %{
              "@type" => "palimpedia:#{edge.edge_type}",
              "target" => "https://palimpedia.org/resource/node/#{edge.target_id}",
              "confidence" => edge.confidence
            }
          end)

        Map.put(item, "palimpedia:relationships", relationships)
      else
        item
      end

    item
  end
end
