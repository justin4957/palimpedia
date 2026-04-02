defmodule Palimpedia.Coverage.BiasAuditorTest do
  use ExUnit.Case, async: false

  alias Palimpedia.Coverage.BiasAuditor

  setup do
    original = Application.get_env(:palimpedia, :graph_repository)
    Application.put_env(:palimpedia, :graph_repository, Palimpedia.Test.MockGraphRepo)
    on_exit(fn -> Application.put_env(:palimpedia, :graph_repository, original) end)
    :ok
  end

  describe "audit/1" do
    test "returns domain coverage analysis" do
      {:ok, result} = BiasAuditor.audit()

      assert is_list(result.domain_coverage)
      assert length(result.domain_coverage) > 0

      for domain_audit <- result.domain_coverage do
        assert Map.has_key?(domain_audit, :domain)
        assert Map.has_key?(domain_audit, :expected_share)
        assert Map.has_key?(domain_audit, :actual_share)
        assert Map.has_key?(domain_audit, :gap)
        assert domain_audit.status in [:balanced, :underrepresented, :overrepresented, :missing]
      end
    end

    test "identifies underrepresented domains" do
      {:ok, result} = BiasAuditor.audit()

      # With mock data (only "Quantum Mechanics" and "Quantum Entanglement"),
      # most domains should be underrepresented or missing
      assert length(result.underrepresented) > 0
    end

    test "computes coverage balance score" do
      {:ok, result} = BiasAuditor.audit()

      assert is_float(result.coverage_balance_score)
      assert result.coverage_balance_score >= 0.0
      assert result.coverage_balance_score <= 1.0
    end

    test "generates recommendations for underrepresented domains" do
      {:ok, result} = BiasAuditor.audit()

      assert is_list(result.recommendations)
      # Should have recommendations for missing/underrepresented domains
      assert length(result.recommendations) > 0
    end

    test "records audit timestamp" do
      {:ok, result} = BiasAuditor.audit()
      assert result.audited_at != nil
    end

    test "can boost underrepresented domains" do
      {:ok, result} = BiasAuditor.audit(boost_underrepresented: true)
      assert is_integer(result.boosted_domains)
    end
  end

  describe "reference_taxonomy/0" do
    test "returns a map of domains with expected shares" do
      taxonomy = BiasAuditor.reference_taxonomy()

      assert is_map(taxonomy)
      assert Map.has_key?(taxonomy, "physics")
      assert Map.has_key?(taxonomy, "philosophy")

      for {_domain, info} <- taxonomy do
        assert Map.has_key?(info, :expected_share)
        assert Map.has_key?(info, :keywords)
        assert info.expected_share > 0
        assert is_list(info.keywords)
      end
    end

    test "expected shares sum to approximately 1.0" do
      total =
        BiasAuditor.reference_taxonomy()
        |> Map.values()
        |> Enum.map(& &1.expected_share)
        |> Enum.sum()

      assert_in_delta total, 1.0, 0.01
    end
  end
end
