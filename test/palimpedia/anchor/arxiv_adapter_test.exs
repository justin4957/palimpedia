defmodule Palimpedia.Anchor.ArxivAdapterTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Anchor.ArxivAdapter

  @single_paper_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <feed xmlns="http://www.w3.org/2005/Atom"
        xmlns:arxiv="http://arxiv.org/schemas/atom">
    <title>ArXiv Query</title>
    <entry>
      <id>http://arxiv.org/abs/2301.07041v1</id>
      <title>Attention Is All You Need: A Review</title>
      <summary>This paper reviews the transformer architecture and its impact on natural language processing and beyond.</summary>
      <published>2023-01-17T12:00:00Z</published>
      <updated>2023-01-17T12:00:00Z</updated>
      <author><name>Alice Researcher</name></author>
      <author><name>Bob Scientist</name></author>
      <category term="cs.CL" />
      <category term="cs.AI" />
      <arxiv:doi>10.1234/example.2023</arxiv:doi>
    </entry>
  </feed>
  """

  @multi_paper_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <feed xmlns="http://www.w3.org/2005/Atom"
        xmlns:arxiv="http://arxiv.org/schemas/atom">
    <title>ArXiv Query</title>
    <entry>
      <id>http://arxiv.org/abs/2301.07041v1</id>
      <title>Paper One: Transformers</title>
      <summary>Abstract about transformers.</summary>
      <published>2023-01-17T12:00:00Z</published>
      <updated>2023-01-17T12:00:00Z</updated>
      <author><name>Alice Researcher</name></author>
      <category term="cs.CL" />
    </entry>
    <entry>
      <id>http://arxiv.org/abs/2302.08042v1</id>
      <title>Paper Two: Attention Mechanisms</title>
      <summary>Abstract about attention.</summary>
      <published>2023-02-15T12:00:00Z</published>
      <updated>2023-02-15T12:00:00Z</updated>
      <author><name>Charlie Developer</name></author>
      <category term="cs.CL" />
    </entry>
    <entry>
      <id>http://arxiv.org/abs/2303.09043v1</id>
      <title>Paper Three: Quantum Computing</title>
      <summary>Abstract about quantum.</summary>
      <published>2023-03-20T12:00:00Z</published>
      <updated>2023-03-20T12:00:00Z</updated>
      <author><name>Diana Physicist</name></author>
      <category term="quant-ph" />
    </entry>
  </feed>
  """

  @empty_feed_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <feed xmlns="http://www.w3.org/2005/Atom">
    <title>ArXiv Query</title>
  </feed>
  """

  defp mock_http(response_body, expected_status \\ 200) do
    fn _url, _opts ->
      {:ok, %{status: expected_status, body: response_body, headers: []}}
    end
  end

  describe "fetch_entity/2" do
    test "fetches and parses a single arXiv paper" do
      assert {:ok, result} =
               ArxivAdapter.fetch_entity("2301.07041", http_client: mock_http(@single_paper_xml))

      assert length(result.entities) == 1

      [entity] = result.entities
      assert entity.title == "Attention Is All You Need: A Review"
      assert entity.source_id == "arxiv:2301.07041v1"
      assert String.contains?(entity.content, "transformer architecture")
      assert entity.properties.authors == ["Alice Researcher", "Bob Scientist"]
      assert "cs.CL" in entity.properties.categories
      assert "cs.AI" in entity.properties.categories
      assert entity.properties.doi == "10.1234/example.2023"
    end
  end

  describe "fetch_entities/2" do
    test "fetches multiple papers and creates category-based relationships" do
      assert {:ok, result} =
               ArxivAdapter.fetch_entities(["2301.07041", "2302.08042", "2303.09043"],
                 http_client: mock_http(@multi_paper_xml)
               )

      assert length(result.entities) == 3

      titles = Enum.map(result.entities, & &1.title) |> MapSet.new()
      assert "Paper One: Transformers" in titles
      assert "Paper Two: Attention Mechanisms" in titles
      assert "Paper Three: Quantum Computing" in titles

      # Papers 1 and 2 share cs.CL category -> related_to edge
      cs_cl_rels =
        Enum.filter(result.relationships, fn rel ->
          (rel.source_id == "arxiv:2301.07041v1" and rel.target_id == "arxiv:2302.08042v1") or
            (rel.source_id == "arxiv:2302.08042v1" and rel.target_id == "arxiv:2301.07041v1")
        end)

      assert length(cs_cl_rels) > 0
      assert hd(cs_cl_rels).edge_type == :related_to
    end

    test "handles empty feed" do
      assert {:ok, result} =
               ArxivAdapter.fetch_entities(["nonexistent"],
                 http_client: mock_http(@empty_feed_xml)
               )

      assert result.entities == []
      assert result.relationships == []
    end
  end

  describe "search/2" do
    test "searches arXiv and returns parsed results" do
      assert {:ok, result} =
               ArxivAdapter.search("transformer attention",
                 http_client: mock_http(@multi_paper_xml),
                 limit: 10
               )

      assert length(result.entities) == 3
    end
  end

  describe "error handling" do
    test "returns error on HTTP failure" do
      mock_fn = fn _url, _opts -> {:error, :timeout} end

      assert {:error, :timeout} =
               ArxivAdapter.fetch_entity("2301.07041", http_client: mock_fn)
    end

    test "returns error on non-200 status" do
      assert {:error, {:http_error, 503}} =
               ArxivAdapter.fetch_entity("2301.07041", http_client: mock_http("", 503))
    end
  end

  describe "entity properties" do
    test "all entities are tagged as arxiv sources" do
      assert {:ok, result} =
               ArxivAdapter.fetch_entities(["2301.07041"],
                 http_client: mock_http(@single_paper_xml)
               )

      for entity <- result.entities do
        assert String.starts_with?(entity.source_id, "arxiv:")
      end
    end

    test "content includes authors and abstract" do
      assert {:ok, result} =
               ArxivAdapter.fetch_entity("2301.07041", http_client: mock_http(@single_paper_xml))

      [entity] = result.entities
      assert String.contains?(entity.content, "Alice Researcher")
      assert String.contains?(entity.content, "Bob Scientist")
      assert String.contains?(entity.content, "transformer architecture")
    end
  end
end
