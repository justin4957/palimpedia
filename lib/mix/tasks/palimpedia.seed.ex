defmodule Mix.Tasks.Palimpedia.Seed do
  @moduledoc """
  Seeds the graph with anchor corpus entities from curated domain lists.

  ## Usage

      # Seed all domains
      mix palimpedia.seed

      # Seed specific domains
      mix palimpedia.seed --domains physics,philosophy

      # Dry run (show what would be ingested without hitting APIs)
      mix palimpedia.seed --dry-run

      # Limit entities per domain (for testing)
      mix palimpedia.seed --limit 50

      # Set delay between API batches (ms, for rate limiting)
      mix palimpedia.seed --delay 1000

  ## Domains

  Physics, Philosophy, Mathematics, Computer Science, Legal History, Political Science.

  Each domain uses Wikidata root QIDs, search queries, and (where applicable)
  arXiv paper queries to build the anchor corpus.
  """

  use Mix.Task

  alias Palimpedia.Anchor.{Ingestion, WikidataAdapter, ArxivAdapter}
  alias Palimpedia.Anchor.Corpus.SeedCorpus

  @shortdoc "Seed the graph with 10,000+ anchor-grounded nodes"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_opts(args)
    selected_domains = select_domains(opts)

    if opts[:dry_run] do
      dry_run(selected_domains)
    else
      seed(selected_domains, opts)
    end
  end

  defp parse_opts(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          domains: :string,
          dry_run: :boolean,
          limit: :integer,
          delay: :integer
        ]
      )

    opts
  end

  defp select_domains(opts) do
    case opts[:domains] do
      nil ->
        SeedCorpus.domains()

      domain_str ->
        requested = String.split(domain_str, ",") |> Enum.map(&String.trim/1)

        SeedCorpus.domains()
        |> Enum.filter(fn d -> d.name in requested end)
    end
  end

  defp dry_run(domains) do
    Mix.shell().info("=== Dry Run: Seed Corpus Plan ===\n")

    total = 0

    total =
      Enum.reduce(domains, total, fn domain, acc ->
        qid_count = length(domain.wikidata_root_qids)
        search_count = length(domain.wikidata_search_queries)
        arxiv_count = length(domain.arxiv_queries)

        Mix.shell().info("Domain: #{domain.name}")
        Mix.shell().info("  Wikidata root QIDs: #{qid_count}")
        Mix.shell().info("  Wikidata search queries: #{search_count}")
        Mix.shell().info("  arXiv queries: #{arxiv_count}")
        Mix.shell().info("  Estimated entities: #{domain.estimated_entities}")
        Mix.shell().info("")

        acc + domain.estimated_entities
      end)

    Mix.shell().info("Total estimated entities: #{total}")
    Mix.shell().info("Total domains: #{length(domains)}")
  end

  defp seed(domains, opts) do
    limit = opts[:limit]
    delay_ms = opts[:delay] || 500

    Mix.shell().info("=== Seeding Anchor Corpus ===\n")

    total_result =
      Enum.reduce(domains, %{nodes: 0, edges: 0, errors: 0}, fn domain, acc ->
        Mix.shell().info("--- Domain: #{domain.name} ---")

        domain_result = seed_domain(domain, limit, delay_ms)

        Mix.shell().info(
          "  Nodes: #{domain_result.nodes}, Edges: #{domain_result.edges}, Errors: #{domain_result.errors}\n"
        )

        %{
          nodes: acc.nodes + domain_result.nodes,
          edges: acc.edges + domain_result.edges,
          errors: acc.errors + domain_result.errors
        }
      end)

    Mix.shell().info("=== Seed Complete ===")
    Mix.shell().info("Total nodes created: #{total_result.nodes}")
    Mix.shell().info("Total edges created: #{total_result.edges}")
    Mix.shell().info("Total errors: #{total_result.errors}")
  end

  defp seed_domain(domain, limit, delay_ms) do
    # Phase 1: Ingest root QIDs
    qids = maybe_limit(domain.wikidata_root_qids, limit)
    qid_result = ingest_wikidata_qids(qids, delay_ms)

    # Phase 2: Ingest from search queries
    searches = maybe_limit(domain.wikidata_search_queries, limit)
    search_result = ingest_wikidata_searches(searches, limit || 50, delay_ms)

    # Phase 3: Ingest arXiv papers
    arxiv_queries = maybe_limit(domain.arxiv_queries, limit)
    arxiv_result = ingest_arxiv_searches(arxiv_queries, limit || 20, delay_ms)

    %{
      nodes: qid_result.nodes + search_result.nodes + arxiv_result.nodes,
      edges: qid_result.edges + search_result.edges + arxiv_result.edges,
      errors: qid_result.errors + search_result.errors + arxiv_result.errors
    }
  end

  defp ingest_wikidata_qids(qids, delay_ms) do
    if qids == [] do
      %{nodes: 0, edges: 0, errors: 0}
    else
      Mix.shell().info("  Ingesting #{length(qids)} Wikidata root entities...")
      result = Ingestion.ingest_entities(WikidataAdapter, qids, batch_size: 20)
      Process.sleep(delay_ms)

      %{
        nodes: result.nodes_created,
        edges: result.edges_created,
        errors: length(result.errors)
      }
    end
  end

  defp ingest_wikidata_searches(queries, limit_per_query, delay_ms) do
    Enum.reduce(queries, %{nodes: 0, edges: 0, errors: 0}, fn query, acc ->
      Mix.shell().info("  Searching Wikidata: \"#{query}\"...")

      case Ingestion.ingest_search(WikidataAdapter, query, limit: limit_per_query) do
        {:ok, result} ->
          Process.sleep(delay_ms)

          %{
            nodes: acc.nodes + result.nodes_created,
            edges: acc.edges + result.edges_created,
            errors: acc.errors + length(result.errors)
          }
      end
    end)
  end

  defp ingest_arxiv_searches(queries, limit_per_query, delay_ms) do
    Enum.reduce(queries, %{nodes: 0, edges: 0, errors: 0}, fn query, acc ->
      Mix.shell().info("  Searching arXiv: \"#{query}\"...")

      case Ingestion.ingest_search(ArxivAdapter, query, limit: limit_per_query) do
        {:ok, result} ->
          Process.sleep(delay_ms)

          %{
            nodes: acc.nodes + result.nodes_created,
            edges: acc.edges + result.edges_created,
            errors: acc.errors + length(result.errors)
          }
      end
    end)
  end

  defp maybe_limit(list, nil), do: list
  defp maybe_limit(list, limit), do: Enum.take(list, limit)
end
