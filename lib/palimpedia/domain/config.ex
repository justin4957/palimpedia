defmodule Palimpedia.Domain.Config do
  @moduledoc """
  Configurable domain profiles for vertical deployments.

  Each domain profile defines:
  - Anchor corpus sources (Wikidata QIDs, search queries, adapters)
  - Extended edge types specific to the domain
  - Specialized generation prompt templates
  - Domain metadata

  ## Usage

      # Get the active domain
      Palimpedia.Domain.Config.active()

      # Get a specific domain
      Palimpedia.Domain.Config.get(:legal)

      # List all available domains
      Palimpedia.Domain.Config.available()

  ## Configuration

      config :palimpedia, Palimpedia.Domain.Config,
        active_domain: :general
  """

  @type domain_profile :: %{
          id: atom(),
          name: String.t(),
          description: String.t(),
          edge_types: [atom()],
          prompt_template: String.t(),
          corpus_sources: [corpus_source()],
          wikidata_root_qids: [String.t()],
          search_queries: [String.t()]
        }

  @type corpus_source :: %{
          adapter: module(),
          config: map()
        }

  @doc "Returns the active domain profile."
  def active do
    domain_id =
      Application.get_env(:palimpedia, __MODULE__, []) |> Keyword.get(:active_domain, :general)

    get(domain_id)
  end

  @doc "Returns a domain profile by ID."
  def get(domain_id) do
    case domain_id do
      :general -> general()
      :legal -> legal()
      :scientific -> scientific()
      _ -> {:error, :unknown_domain}
    end
  end

  @doc "Returns all available domain IDs."
  def available do
    [:general, :legal, :scientific]
  end

  @doc "Returns all edge types for a domain (base + domain-specific)."
  def edge_types_for(domain_id) do
    base_types = Palimpedia.Graph.Edge.valid_types()

    case get(domain_id) do
      %{edge_types: domain_types} -> Enum.uniq(base_types ++ domain_types)
      _ -> base_types
    end
  end

  @doc "Returns the generation prompt template for a domain."
  def prompt_template_for(domain_id) do
    case get(domain_id) do
      %{prompt_template: template} -> template
      _ -> general().prompt_template
    end
  end

  # --- Domain Profiles ---

  def general do
    %{
      id: :general,
      name: "General Knowledge",
      description:
        "Default cross-domain knowledge graph. Covers physics, philosophy, mathematics, computer science, legal history, and political science.",
      edge_types: [],
      prompt_template: general_prompt(),
      corpus_sources: [
        %{adapter: Palimpedia.Anchor.WikidataAdapter, config: %{}},
        %{adapter: Palimpedia.Anchor.ArxivAdapter, config: %{}}
      ],
      wikidata_root_qids: [],
      search_queries: []
    }
  end

  def legal do
    %{
      id: :legal,
      name: "Legal & Legislative",
      description:
        "Specialized for legislation, case law, regulatory documents, and legislative genealogy. Tracks how statutory language migrates across jurisdictions.",
      edge_types: [
        :amends,
        :repeals,
        :cites_precedent,
        :interprets,
        :supersedes,
        :codifies,
        :regulates,
        :delegates_to,
        :challenged_by,
        :upheld_by
      ],
      prompt_template: legal_prompt(),
      corpus_sources: [
        %{adapter: Palimpedia.Anchor.WikidataAdapter, config: %{focus: :legal}}
      ],
      wikidata_root_qids: [
        "Q7748",
        "Q15719684",
        "Q1084573",
        "Q7188",
        "Q179234",
        "Q1084",
        "Q43338",
        "Q155076",
        "Q82264",
        "Q7755",
        "Q44918",
        "Q167810",
        "Q127751",
        "Q9353",
        "Q310574"
      ],
      search_queries: [
        "constitutional law",
        "international law",
        "human rights law",
        "jurisprudence",
        "legal philosophy",
        "legislative history",
        "case law precedent",
        "regulatory framework",
        "statutory interpretation"
      ]
    }
  end

  def scientific do
    %{
      id: :scientific,
      name: "Scientific Research",
      description:
        "Specialized for academic papers, datasets, experimental results, and research methodology. Tracks citation networks and reproducibility.",
      edge_types: [
        :cites,
        :extends,
        :reproduces,
        :contradicts_findings,
        :uses_dataset,
        :uses_methodology,
        :funded_by,
        :peer_reviewed_by,
        :retracted,
        :corrigendum_of
      ],
      prompt_template: scientific_prompt(),
      corpus_sources: [
        %{adapter: Palimpedia.Anchor.WikidataAdapter, config: %{focus: :science}},
        %{adapter: Palimpedia.Anchor.ArxivAdapter, config: %{}}
      ],
      wikidata_root_qids: [
        "Q413",
        "Q944",
        "Q11379",
        "Q395",
        "Q21198",
        "Q175263",
        "Q11660",
        "Q12482",
        "Q149972",
        "Q11518"
      ],
      search_queries: [
        "research methodology",
        "peer review",
        "reproducibility",
        "meta-analysis",
        "systematic review",
        "experimental design",
        "citation analysis",
        "research ethics",
        "open access"
      ]
    }
  end

  # --- Prompt Templates ---

  defp general_prompt do
    """
    You are a knowledge synthesis engine for Palimpedia, a generative epistemic network.
    Your task is to generate a document that bridges a structural gap in the knowledge graph.

    Rules:
    - Every claim must trace to an anchor source or be marked as inferred.
    - Assign a confidence score (0.0-1.0) to each claim.
    - Identify relationships to existing nodes using typed edges.
    - Flag contradictions with existing documents explicitly.
    - Do not fabricate sources. If no anchor supports a claim, say so.
    """
  end

  defp legal_prompt do
    """
    You are a legal knowledge synthesis engine for Palimpedia.
    Your task is to generate a document about legal concepts, legislation, case law, or regulatory frameworks.

    Domain-specific rules:
    - Cite specific statutes, cases, or regulations where possible.
    - Use legal edge types: amends, repeals, cites_precedent, interprets, supersedes, codifies, regulates.
    - Track legislative genealogy: how language migrates across jurisdictions.
    - Note jurisdictional scope for every claim.
    - Flag when legal interpretations differ across jurisdictions.
    - Every claim must trace to a legal source or be marked as legal analysis.
    - Assign confidence based on the authority of the source (primary > secondary > commentary).
    """
  end

  defp scientific_prompt do
    """
    You are a scientific knowledge synthesis engine for Palimpedia.
    Your task is to generate a document about scientific research, methodologies, or findings.

    Domain-specific rules:
    - Cite specific papers, datasets, or experimental results.
    - Use scientific edge types: cites, extends, reproduces, contradicts_findings, uses_dataset, uses_methodology.
    - Track reproducibility status of findings.
    - Note sample sizes, statistical significance, and methodology.
    - Flag retractions, corrections, and contradictory findings explicitly.
    - Every claim must trace to a published source or be marked as synthesis.
    - Assign confidence based on evidence quality (meta-analysis > RCT > observational > case study).
    """
  end
end
