defmodule Palimpedia.Domain.ConfigTest do
  use ExUnit.Case, async: true

  alias Palimpedia.Domain.Config

  describe "available/0" do
    test "returns three domain profiles" do
      assert Config.available() == [:general, :legal, :scientific]
    end
  end

  describe "get/1" do
    test "returns general profile" do
      profile = Config.get(:general)
      assert profile.id == :general
      assert profile.name == "General Knowledge"
      assert is_binary(profile.description)
      assert is_binary(profile.prompt_template)
    end

    test "returns legal profile with domain-specific edge types" do
      profile = Config.get(:legal)
      assert profile.id == :legal
      assert :amends in profile.edge_types
      assert :cites_precedent in profile.edge_types
      assert :repeals in profile.edge_types
      assert :supersedes in profile.edge_types
      assert length(profile.wikidata_root_qids) > 0
    end

    test "returns scientific profile with domain-specific edge types" do
      profile = Config.get(:scientific)
      assert profile.id == :scientific
      assert :cites in profile.edge_types
      assert :reproduces in profile.edge_types
      assert :retracted in profile.edge_types
      assert :uses_dataset in profile.edge_types
      assert length(profile.search_queries) > 0
    end

    test "returns error for unknown domain" do
      assert {:error, :unknown_domain} = Config.get(:nonexistent)
    end
  end

  describe "edge_types_for/1" do
    test "general domain has only base types" do
      types = Config.edge_types_for(:general)
      base = Palimpedia.Graph.Edge.valid_types()
      assert types == base
    end

    test "legal domain extends base types" do
      types = Config.edge_types_for(:legal)
      base = Palimpedia.Graph.Edge.valid_types()

      assert length(types) > length(base)
      # All base types present
      for bt <- base, do: assert(bt in types)
      # Legal-specific types present
      assert :amends in types
      assert :cites_precedent in types
    end

    test "scientific domain extends base types" do
      types = Config.edge_types_for(:scientific)
      base = Palimpedia.Graph.Edge.valid_types()

      assert length(types) > length(base)
      assert :cites in types
      assert :reproduces in types
    end
  end

  describe "prompt_template_for/1" do
    test "returns different templates for each domain" do
      general = Config.prompt_template_for(:general)
      legal = Config.prompt_template_for(:legal)
      scientific = Config.prompt_template_for(:scientific)

      assert general != legal
      assert legal != scientific
      assert String.contains?(legal, "legal")
      assert String.contains?(scientific, "scientific")
    end
  end

  describe "domain profiles" do
    test "legal profile has use-case-appropriate content" do
      profile = Config.get(:legal)

      assert String.contains?(profile.description, "legislation")
      assert String.contains?(profile.prompt_template, "statute")
      assert "Q7748" in profile.wikidata_root_qids
    end

    test "scientific profile has use-case-appropriate content" do
      profile = Config.get(:scientific)

      assert String.contains?(profile.description, "papers")
      assert String.contains?(profile.prompt_template, "reproducibility")
      assert Enum.any?(profile.search_queries, &String.contains?(&1, "peer review"))
    end

    test "all profiles have required fields" do
      for domain_id <- Config.available() do
        profile = Config.get(domain_id)

        assert is_atom(profile.id)
        assert is_binary(profile.name)
        assert is_binary(profile.description)
        assert is_list(profile.edge_types)
        assert is_binary(profile.prompt_template)
        assert is_list(profile.corpus_sources)
      end
    end
  end
end
