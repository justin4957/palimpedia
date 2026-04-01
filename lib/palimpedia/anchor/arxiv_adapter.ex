defmodule Palimpedia.Anchor.ArxivAdapter do
  @moduledoc """
  Adapter for ingesting papers from the arXiv preprint server.

  Fetches papers by arXiv ID or search query via the arXiv API.
  Extracts title, abstract, authors, categories, and cross-references.
  """

  @behaviour Palimpedia.Anchor.Adapter

  @base_url "http://export.arxiv.org/api/query"

  # arXiv category -> broad domain for metadata
  @category_domains %{
    "cs" => "Computer Science",
    "math" => "Mathematics",
    "physics" => "Physics",
    "q-bio" => "Quantitative Biology",
    "q-fin" => "Quantitative Finance",
    "stat" => "Statistics",
    "eess" => "Electrical Engineering",
    "econ" => "Economics",
    "astro-ph" => "Astrophysics",
    "cond-mat" => "Condensed Matter",
    "hep" => "High Energy Physics",
    "quant-ph" => "Quantum Physics"
  }

  @impl true
  def fetch_entity(arxiv_id, opts \\ []) do
    fetch_entities([arxiv_id], opts)
  end

  @impl true
  def fetch_entities(arxiv_ids, opts \\ []) do
    http_get = Keyword.get(opts, :http_client, &Palimpedia.Anchor.HttpClient.get/2)

    id_query = Enum.map_join(arxiv_ids, "+OR+", fn id -> "id:#{id}" end)
    url = "#{@base_url}?search_query=#{id_query}&max_results=#{length(arxiv_ids)}"

    case http_get.(url, []) do
      {:ok, %{status: 200, body: body}} ->
        parse_atom_feed(body)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def search(query, opts \\ []) do
    http_get = Keyword.get(opts, :http_client, &Palimpedia.Anchor.HttpClient.get/2)
    limit = Keyword.get(opts, :limit, 20)

    encoded_query = URI.encode(query)
    url = "#{@base_url}?search_query=all:#{encoded_query}&start=0&max_results=#{limit}"

    case http_get.(url, []) do
      {:ok, %{status: 200, body: body}} ->
        parse_atom_feed(body)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns category domain mappings."
  def category_domains, do: @category_domains

  # --- Atom XML Parsing ---

  defp parse_atom_feed(xml_body) when is_binary(xml_body) do
    entries = extract_entries(xml_body)

    entities =
      Enum.map(entries, fn entry ->
        arxiv_id = extract_arxiv_id(entry)

        %{
          title: extract_tag(entry, "title"),
          content: build_content(entry),
          source_id: "arxiv:#{arxiv_id}",
          properties: %{
            arxiv_id: arxiv_id,
            authors: extract_authors(entry),
            categories: extract_categories(entry),
            published: extract_tag(entry, "published"),
            updated: extract_tag(entry, "updated"),
            doi: extract_doi(entry)
          }
        }
      end)

    # arXiv doesn't expose citation graphs directly via the API.
    # Cross-references between papers sharing categories create related_to edges.
    relationships = build_category_relationships(entities)

    {:ok, %{entities: entities, relationships: relationships}}
  end

  defp extract_entries(xml) do
    # Split on <entry> tags — lightweight XML extraction without a full parser dependency
    xml
    |> String.split(~r/<entry>/)
    |> Enum.drop(1)
    |> Enum.map(fn segment ->
      case String.split(segment, ~r/<\/entry>/, parts: 2) do
        [entry_content | _] -> entry_content
        _ -> ""
      end
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp extract_tag(entry, tag_name) do
    case Regex.run(~r/<#{tag_name}[^>]*>(.*?)<\/#{tag_name}>/s, entry) do
      [_, content] -> content |> String.trim() |> normalize_whitespace()
      _ -> ""
    end
  end

  defp extract_arxiv_id(entry) do
    case Regex.run(~r/<id>http:\/\/arxiv\.org\/abs\/(.*?)<\/id>/, entry) do
      [_, arxiv_id] -> arxiv_id
      _ -> extract_id_fallback(entry)
    end
  end

  defp extract_id_fallback(entry) do
    case Regex.run(~r/<id>(.*?)<\/id>/, entry) do
      [_, raw_id] -> raw_id |> String.replace("http://arxiv.org/abs/", "")
      _ -> "unknown"
    end
  end

  defp extract_authors(entry) do
    Regex.scan(~r/<author>\s*<name>(.*?)<\/name>/s, entry)
    |> Enum.map(fn [_, name] -> String.trim(name) end)
  end

  defp extract_categories(entry) do
    Regex.scan(~r/<category[^>]*term="([^"]+)"/, entry)
    |> Enum.map(fn [_, category] -> category end)
  end

  defp extract_doi(entry) do
    case Regex.run(~r/<arxiv:doi[^>]*>(.*?)<\/arxiv:doi>/, entry) do
      [_, doi] -> doi
      _ -> nil
    end
  end

  defp build_content(entry) do
    title = extract_tag(entry, "title")
    abstract = extract_tag(entry, "summary")
    authors = extract_authors(entry) |> Enum.join(", ")
    categories = extract_categories(entry) |> Enum.join(", ")

    """
    #{title}

    Authors: #{authors}
    Categories: #{categories}

    #{abstract}
    """
    |> String.trim()
  end

  defp build_category_relationships(entities) do
    # Group entities by their primary category, then create related_to
    # edges between papers in the same category
    entities
    |> Enum.reduce(%{}, fn entity, by_category ->
      primary_category = entity.properties.categories |> List.first() || "unknown"

      Map.update(by_category, primary_category, [entity.source_id], fn ids ->
        [entity.source_id | ids]
      end)
    end)
    |> Enum.flat_map(fn {_category, source_ids} ->
      # Create pairwise relationships within each category (limit to avoid O(n^2))
      source_ids
      |> Enum.take(10)
      |> pairs()
      |> Enum.map(fn {source_id, target_id} ->
        %{
          source_id: source_id,
          target_id: target_id,
          edge_type: :related_to,
          confidence: 0.8
        }
      end)
    end)
  end

  defp pairs(list) do
    for {a, i} <- Enum.with_index(list),
        {b, j} <- Enum.with_index(list),
        i < j,
        do: {a, b}
  end

  defp normalize_whitespace(text) do
    text |> String.replace(~r/\s+/, " ") |> String.trim()
  end
end
