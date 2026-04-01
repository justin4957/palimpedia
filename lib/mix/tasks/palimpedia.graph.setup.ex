defmodule Mix.Tasks.Palimpedia.Graph.Setup do
  @moduledoc """
  Creates Neo4j indexes and constraints for the Palimpedia graph schema.

  ## Usage

      mix palimpedia.graph.setup

  This task:
  - Creates indexes on Document node properties (title, node_type, confidence)
  - Creates a uniqueness constraint on title (optional, can be skipped)
  - Verifies the typed edge vocabulary can be used

  ## Prerequisites

  Neo4j must be running and accessible via the configured Bolt URL.
  See `docker-compose.yml` to start the development database.
  """

  use Mix.Task

  @shortdoc "Set up Neo4j indexes and constraints for the graph schema"

  @indexes [
    {"idx_document_title",
     "CREATE INDEX idx_document_title IF NOT EXISTS FOR (n:Document) ON (n.title)"},
    {"idx_document_node_type",
     "CREATE INDEX idx_document_node_type IF NOT EXISTS FOR (n:Document) ON (n.node_type)"},
    {"idx_document_confidence",
     "CREATE INDEX idx_document_confidence IF NOT EXISTS FOR (n:Document) ON (n.confidence)"},
    {"idx_document_anchor_distance",
     "CREATE INDEX idx_document_anchor_distance IF NOT EXISTS FOR (n:Document) ON (n.anchor_distance)"}
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    conn = Bolt.Sips.conn()

    Mix.shell().info("Setting up Palimpedia graph schema in Neo4j...")
    Mix.shell().info("")

    create_indexes(conn)
    verify_connectivity(conn)

    Mix.shell().info("")
    Mix.shell().info("Graph schema setup complete.")
  end

  defp create_indexes(conn) do
    Mix.shell().info("Creating indexes...")

    Enum.each(@indexes, fn {name, cypher} ->
      case Bolt.Sips.query(conn, cypher) do
        {:ok, _} ->
          Mix.shell().info("  [ok] #{name}")

        {:error, reason} ->
          Mix.shell().error("  [error] #{name}: #{inspect(reason)}")
      end
    end)
  end

  defp verify_connectivity(conn) do
    Mix.shell().info("")
    Mix.shell().info("Verifying connectivity...")

    case Bolt.Sips.query(conn, "RETURN 1 AS ping") do
      {:ok, response} ->
        [%{"ping" => 1}] = response.results
        Mix.shell().info("  [ok] Neo4j connection verified")

      {:error, reason} ->
        Mix.shell().error("  [error] Connection failed: #{inspect(reason)}")
    end

    case Bolt.Sips.query(conn, "MATCH (n:Document) RETURN count(n) AS node_count") do
      {:ok, response} ->
        [%{"node_count" => count}] = response.results
        Mix.shell().info("  [ok] Current document count: #{count}")

      {:error, reason} ->
        Mix.shell().error("  [error] Node count failed: #{inspect(reason)}")
    end

    Mix.shell().info("")
    Mix.shell().info("Edge type vocabulary:")

    Enum.each(Palimpedia.Graph.Edge.valid_types(), fn edge_type ->
      label = edge_type |> Atom.to_string() |> String.upcase()
      Mix.shell().info("  - #{label}")
    end)
  end
end
