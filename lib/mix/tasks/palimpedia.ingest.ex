defmodule Mix.Tasks.Palimpedia.Ingest do
  @moduledoc """
  Ingests entities from an anchor corpus source into the graph.

  ## Usage

      # Ingest specific Wikidata entities by QID
      mix palimpedia.ingest wikidata Q42 Q5 Q944 Q11379

      # Search and ingest from Wikidata
      mix palimpedia.ingest wikidata --search "quantum mechanics" --limit 20

      # Ingest arXiv papers by ID
      mix palimpedia.ingest arxiv 2301.07041 2302.08042

      # Search and ingest from arXiv
      mix palimpedia.ingest arxiv --search "transformer attention" --limit 10

  ## Prerequisites

  Neo4j must be running. See `docker-compose.yml`.
  """

  use Mix.Task

  alias Palimpedia.Anchor.{Ingestion, WikidataAdapter, ArxivAdapter}

  @shortdoc "Ingest anchor corpus entities from Wikidata or arXiv"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case parse_args(args) do
      {:entities, adapter, identifiers} ->
        ingest_by_ids(adapter, identifiers)

      {:search, adapter, query, limit} ->
        ingest_by_search(adapter, query, limit)

      :error ->
        Mix.shell().error(
          "Usage: mix palimpedia.ingest <wikidata|arxiv> [IDs...] [--search QUERY]"
        )
    end
  end

  defp parse_args([source | rest]) do
    adapter = resolve_adapter(source)

    if is_nil(adapter) do
      :error
    else
      case parse_options(rest) do
        {:search, query, limit} -> {:search, adapter, query, limit}
        {:ids, ids} -> {:entities, adapter, ids}
        :error -> :error
      end
    end
  end

  defp parse_args(_), do: :error

  defp resolve_adapter("wikidata"), do: WikidataAdapter
  defp resolve_adapter("arxiv"), do: ArxivAdapter
  defp resolve_adapter(_), do: nil

  defp parse_options(args) do
    case OptionParser.parse(args, strict: [search: :string, limit: :integer]) do
      {opts, remaining_ids, _} ->
        if opts[:search] do
          {:search, opts[:search], opts[:limit] || 20}
        else
          if remaining_ids == [] do
            :error
          else
            {:ids, remaining_ids}
          end
        end
    end
  end

  defp ingest_by_ids(adapter, identifiers) do
    adapter_name = adapter_label(adapter)
    Mix.shell().info("Ingesting #{length(identifiers)} entities from #{adapter_name}...")

    result = Ingestion.ingest_entities(adapter, identifiers)
    print_result(result)
  end

  defp ingest_by_search(adapter, query, limit) do
    adapter_name = adapter_label(adapter)
    Mix.shell().info("Searching #{adapter_name} for \"#{query}\" (limit: #{limit})...")

    {:ok, result} = Ingestion.ingest_search(adapter, query, limit: limit)
    print_result(result)
  end

  defp print_result(result) do
    Mix.shell().info("")
    Mix.shell().info("Ingestion complete:")
    Mix.shell().info("  Nodes created: #{result.nodes_created}")
    Mix.shell().info("  Edges created: #{result.edges_created}")

    if result.errors != [] do
      Mix.shell().info("  Errors: #{length(result.errors)}")

      for error <- Enum.take(result.errors, 5) do
        Mix.shell().error("    - #{inspect(error)}")
      end

      if length(result.errors) > 5 do
        Mix.shell().error("    ... and #{length(result.errors) - 5} more")
      end
    end
  end

  defp adapter_label(WikidataAdapter), do: "Wikidata"
  defp adapter_label(ArxivAdapter), do: "arXiv"
  defp adapter_label(module), do: inspect(module)
end
