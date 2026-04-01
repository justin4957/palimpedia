defmodule Palimpedia.Anchor.Corpus.SeedCorpusTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Anchor.Corpus.SeedCorpus

  describe "domains/0" do
    test "returns all 6 domains" do
      domains = SeedCorpus.domains()
      assert length(domains) == 6
    end

    test "all domains have required fields" do
      for domain <- SeedCorpus.domains() do
        assert is_binary(domain.name), "domain missing name"
        assert is_list(domain.wikidata_root_qids), "#{domain.name} missing root QIDs"
        assert is_list(domain.wikidata_search_queries), "#{domain.name} missing search queries"
        assert is_list(domain.arxiv_queries), "#{domain.name} missing arXiv queries"
        assert is_integer(domain.estimated_entities), "#{domain.name} missing estimated_entities"
        assert domain.estimated_entities > 0, "#{domain.name} has zero entities"
      end
    end

    test "all QIDs are valid format" do
      for domain <- SeedCorpus.domains() do
        for qid <- domain.wikidata_root_qids do
          assert Regex.match?(~r/^Q\d+$/, qid),
                 "Invalid QID #{qid} in domain #{domain.name}"
        end
      end
    end

    test "no duplicate QIDs within a domain" do
      for domain <- SeedCorpus.domains() do
        qids = domain.wikidata_root_qids

        assert length(qids) == length(Enum.uniq(qids)),
               "Duplicate QIDs in domain #{domain.name}"
      end
    end
  end

  describe "domain/1" do
    test "returns a specific domain by name" do
      domain = SeedCorpus.domain("physics")
      assert domain.name == "physics"
      assert length(domain.wikidata_root_qids) > 0
    end

    test "returns nil for unknown domain" do
      assert SeedCorpus.domain("nonexistent") == nil
    end
  end

  describe "domain_names/0" do
    test "returns all domain names" do
      names = SeedCorpus.domain_names()
      assert "physics" in names
      assert "philosophy" in names
      assert "mathematics" in names
      assert "computer_science" in names
      assert "legal_history" in names
      assert "political_science" in names
    end
  end

  describe "total_estimated_entities/0" do
    test "sums to approximately 10,000" do
      total = SeedCorpus.total_estimated_entities()
      assert total >= 10_000, "Total estimated entities #{total} is less than 10,000"
    end
  end

  describe "individual domains" do
    test "physics has root QIDs for key concepts and physicists" do
      domain = SeedCorpus.physics()
      qids = domain.wikidata_root_qids

      # Key concepts
      # quantum mechanics
      assert "Q944" in qids
      # general relativity
      assert "Q11379" in qids

      # Key figures
      # Einstein
      assert "Q937" in qids
      # Newton
      assert "Q7312" in qids

      # Has arXiv queries
      assert length(domain.arxiv_queries) > 0
    end

    test "philosophy has root QIDs for branches and philosophers" do
      domain = SeedCorpus.philosophy()
      qids = domain.wikidata_root_qids

      # Aristotle
      assert "Q868" in qids
      # Plato
      assert "Q859" in qids
      # Kant
      assert "Q9312" in qids
    end

    test "computer_science has arXiv queries for modern topics" do
      domain = SeedCorpus.computer_science()

      arxiv_topics = domain.arxiv_queries |> Enum.join(" ")

      assert String.contains?(arxiv_topics, "transformer") or
               String.contains?(arxiv_topics, "language model") or
               String.contains?(arxiv_topics, "neural")
    end

    test "legal_history has no arXiv queries" do
      domain = SeedCorpus.legal_history()
      assert domain.arxiv_queries == []
    end
  end
end
