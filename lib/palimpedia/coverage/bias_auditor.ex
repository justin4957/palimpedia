defmodule Palimpedia.Coverage.BiasAuditor do
  @moduledoc """
  Periodic bias audit: compares graph coverage against a reference
  knowledge taxonomy to detect epistemic closure.

  "System generates only what its seed corpus encodes. Marginalized
  knowledge never has relational density to trigger generation."

  ## Mitigations

  1. Compare coverage by domain against reference taxonomy
  2. Identify underrepresented domains
  3. Boost generation priority for low-coverage areas
  4. Document blind spots as first-class system output
  """

  alias Palimpedia.GapDetection.GenerationQueue

  require Logger

  @reference_taxonomy %{
    "physics" => %{
      expected_share: 0.15,
      keywords: ["physics", "quantum", "relativity", "thermodynamics"]
    },
    "philosophy" => %{
      expected_share: 0.12,
      keywords: ["philosophy", "epistemology", "ethics", "metaphysics"]
    },
    "mathematics" => %{
      expected_share: 0.12,
      keywords: ["mathematics", "algebra", "topology", "calculus"]
    },
    "computer_science" => %{
      expected_share: 0.12,
      keywords: ["computer", "algorithm", "machine learning", "artificial intelligence"]
    },
    "legal" => %{
      expected_share: 0.10,
      keywords: ["law", "legal", "constitutional", "jurisprudence"]
    },
    "political_science" => %{
      expected_share: 0.08,
      keywords: ["politics", "democracy", "governance", "sovereignty"]
    },
    "biology" => %{
      expected_share: 0.08,
      keywords: ["biology", "genetics", "evolution", "ecology"]
    },
    "history" => %{
      expected_share: 0.08,
      keywords: ["history", "historical", "civilization", "century"]
    },
    "sociology" => %{
      expected_share: 0.05,
      keywords: ["sociology", "social", "culture", "inequality"]
    },
    "economics" => %{expected_share: 0.05, keywords: ["economics", "market", "trade", "monetary"]},
    "arts" => %{expected_share: 0.05, keywords: ["art", "music", "literature", "theater"]}
  }

  @type audit_result :: %{
          domain_coverage: [domain_audit()],
          underrepresented: [String.t()],
          overrepresented: [String.t()],
          coverage_balance_score: float(),
          boosted_domains: non_neg_integer(),
          recommendations: [String.t()],
          audited_at: DateTime.t()
        }

  @type domain_audit :: %{
          domain: String.t(),
          expected_share: float(),
          actual_share: float(),
          gap: float(),
          status: :balanced | :underrepresented | :overrepresented | :missing
        }

  @doc """
  Runs a full bias audit comparing graph coverage against the reference taxonomy.
  Optionally boosts generation priority for underrepresented domains.
  """
  def audit(opts \\ []) do
    graph_repo = Keyword.get(opts, :graph_repo, graph_repository())
    boost = Keyword.get(opts, :boost_underrepresented, false)

    # Get current graph state
    case graph_repo.search_nodes("", limit: 50_000) do
      {:ok, nodes} ->
        total = length(nodes)
        domain_audits = audit_domains(nodes, total)

        underrepresented =
          domain_audits
          |> Enum.filter(&(&1.status in [:underrepresented, :missing]))
          |> Enum.map(& &1.domain)

        overrepresented =
          domain_audits
          |> Enum.filter(&(&1.status == :overrepresented))
          |> Enum.map(& &1.domain)

        balance_score = compute_balance_score(domain_audits)

        boosted =
          if boost do
            boost_underrepresented(underrepresented)
          else
            0
          end

        recommendations = generate_recommendations(domain_audits, underrepresented)

        {:ok,
         %{
           domain_coverage: domain_audits,
           underrepresented: underrepresented,
           overrepresented: overrepresented,
           coverage_balance_score: Float.round(balance_score, 3),
           boosted_domains: boosted,
           recommendations: recommendations,
           audited_at: DateTime.utc_now()
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns the reference taxonomy used for bias comparison."
  def reference_taxonomy, do: @reference_taxonomy

  # --- Private ---

  defp audit_domains(nodes, total) do
    Enum.map(@reference_taxonomy, fn {domain, %{expected_share: expected, keywords: keywords}} ->
      matching = count_matching(nodes, keywords)
      actual_share = if total > 0, do: matching / total, else: 0.0
      gap = actual_share - expected

      status =
        cond do
          matching == 0 -> :missing
          gap < -0.05 -> :underrepresented
          gap > 0.10 -> :overrepresented
          true -> :balanced
        end

      %{
        domain: domain,
        expected_share: expected,
        actual_share: Float.round(actual_share, 4),
        gap: Float.round(gap, 4),
        status: status
      }
    end)
    |> Enum.sort_by(& &1.gap)
  end

  defp count_matching(nodes, keywords) do
    Enum.count(nodes, fn node ->
      title_lower = String.downcase(node.title || "")
      content_lower = String.downcase(node.content || "")
      text = title_lower <> " " <> content_lower

      Enum.any?(keywords, &String.contains?(text, &1))
    end)
  end

  defp compute_balance_score(domain_audits) do
    if domain_audits == [] do
      0.0
    else
      gaps = Enum.map(domain_audits, fn d -> abs(d.gap) end)
      avg_gap = Enum.sum(gaps) / length(gaps)
      max(0.0, 1.0 - avg_gap * 5)
    end
  end

  defp boost_underrepresented(domains) do
    if Process.whereis(GenerationQueue) do
      Enum.count(domains, fn domain ->
        gap = %{
          gap_type: :epistemic_closure,
          priority: 7.0,
          suggested_title: "Expand coverage: #{domain}",
          context: %{domain: domain, reason: :bias_audit_boost}
        }

        case GenerationQueue.enqueue(gap) do
          {:ok, _} -> true
          _ -> false
        end
      end)
    else
      0
    end
  end

  defp generate_recommendations(domain_audits, underrepresented) do
    recs = []

    recs =
      Enum.reduce(underrepresented, recs, fn domain, acc ->
        audit = Enum.find(domain_audits, &(&1.domain == domain))

        if audit do
          [
            "Increase #{domain} coverage: currently #{Float.round(audit.actual_share * 100, 1)}% vs expected #{Float.round(audit.expected_share * 100, 1)}%"
            | acc
          ]
        else
          acc
        end
      end)

    missing =
      domain_audits
      |> Enum.filter(&(&1.status == :missing))
      |> Enum.map(fn d ->
        "#{d.domain} has zero representation — consider adding anchor sources"
      end)

    Enum.reverse(recs) ++ missing
  end

  defp graph_repository do
    Application.get_env(:palimpedia, :graph_repository, Palimpedia.Graph.Neo4jRepository)
  end
end
