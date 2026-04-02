defmodule Palimpedia.Export.RDF do
  @moduledoc """
  Exports the knowledge graph as RDF N-Triples.

  Each node becomes an RDF resource with schema.org properties.
  Each edge becomes an RDF triple with a Palimpedia relationship predicate.
  """

  @base_uri "https://palimpedia.org/resource/"
  @schema "http://schema.org/"
  @palimpedia "https://palimpedia.org/ontology/"

  @doc "Exports nodes and edges as RDF N-Triples string."
  def export(nodes, edges) do
    node_triples = Enum.flat_map(nodes, &node_to_triples/1)
    edge_triples = Enum.flat_map(edges, &edge_to_triples(&1, nodes))

    (node_triples ++ edge_triples)
    |> Enum.join("\n")
  end

  @doc "Exports a single node as RDF triples."
  def node_to_triples(node) do
    subject = resource_uri(node.id)

    triples = [
      triple(subject, rdf_type(), schema("Article")),
      triple(subject, schema("name"), literal(node.title)),
      triple(subject, palimpedia("nodeType"), literal(Atom.to_string(node.node_type))),
      triple(subject, palimpedia("confidence"), literal_float(node.confidence))
    ]

    triples =
      if node.content do
        [triple(subject, schema("description"), literal(node.content)) | triples]
      else
        triples
      end

    triples =
      if node.anchor_distance do
        [
          triple(subject, palimpedia("anchorDistance"), literal_int(node.anchor_distance))
          | triples
        ]
      else
        triples
      end

    triples =
      Enum.reduce(node.provenance || [], triples, fn prov, acc ->
        [triple(subject, schema("identifier"), literal(prov)) | acc]
      end)

    triples =
      if node.generated_at do
        [
          triple(subject, schema("dateCreated"), literal(DateTime.to_iso8601(node.generated_at)))
          | triples
        ]
      else
        triples
      end

    Enum.reverse(triples)
  end

  @doc "Exports a single edge as an RDF triple."
  def edge_to_triples(edge, _nodes) do
    source_uri = resource_uri(edge.source_id)
    target_uri = resource_uri(edge.target_id)
    predicate = palimpedia(Atom.to_string(edge.edge_type))

    [
      triple(source_uri, predicate, target_uri),
      triple(source_uri, palimpedia("edgeConfidence"), literal_float(edge.confidence))
    ]
  end

  # --- Helpers ---

  defp resource_uri(id), do: "<#{@base_uri}node/#{id}>"
  defp rdf_type, do: "<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>"
  defp schema(term), do: "<#{@schema}#{term}>"
  defp palimpedia(term), do: "<#{@palimpedia}#{term}>"

  defp literal(value) do
    escaped =
      value
      |> to_string()
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")

    "\"#{escaped}\""
  end

  defp literal_float(value), do: "\"#{value}\"^^<http://www.w3.org/2001/XMLSchema#float>"
  defp literal_int(value), do: "\"#{value}\"^^<http://www.w3.org/2001/XMLSchema#integer>"

  defp triple(subject, predicate, object), do: "#{subject} #{predicate} #{object} ."
end
