defmodule Palimpedia.Anchor.Corpus.SeedCorpus do
  @moduledoc """
  Curated seed corpus definitions for the Phase 0 milestone target:
  10,000+ anchor-grounded nodes with typed edge structure.

  Organized by domain. Each domain provides:
  - Wikidata QIDs for key entities
  - arXiv search queries for paper ingestion
  - Estimated entity count for planning

  ## Domains

  | Domain | Estimated Entities | Source |
  |--------|-------------------|--------|
  | Physics | ~2,500 | Wikidata + arXiv |
  | Philosophy | ~1,500 | Wikidata |
  | Mathematics | ~2,000 | Wikidata + arXiv |
  | Computer Science | ~2,000 | Wikidata + arXiv |
  | Legal History | ~1,000 | Wikidata |
  | Political Science | ~1,000 | Wikidata |
  """

  @type domain :: %{
          name: String.t(),
          wikidata_root_qids: [String.t()],
          wikidata_search_queries: [String.t()],
          arxiv_queries: [String.t()],
          estimated_entities: non_neg_integer()
        }

  @doc "Returns all domain definitions for the seed corpus."
  def domains do
    [
      physics(),
      philosophy(),
      mathematics(),
      computer_science(),
      legal_history(),
      political_science()
    ]
  end

  @doc "Returns a single domain by name."
  def domain(name) do
    Enum.find(domains(), fn d -> d.name == name end)
  end

  @doc "Returns all domain names."
  def domain_names do
    Enum.map(domains(), & &1.name)
  end

  @doc "Returns total estimated entities across all domains."
  def total_estimated_entities do
    Enum.sum(Enum.map(domains(), & &1.estimated_entities))
  end

  def physics do
    %{
      name: "physics",
      wikidata_root_qids: [
        # Core concepts
        # physics
        "Q413",
        # quantum mechanics
        "Q944",
        # general relativity
        "Q11379",
        # special relativity
        "Q11376",
        # classical mechanics
        "Q43518",
        # thermodynamics
        "Q11399",
        # electromagnetism
        "Q11023",
        # optics
        "Q184207",
        # particle physics
        "Q41217",
        # nuclear physics
        "Q208304",
        # condensed matter physics
        "Q184624",
        # statistical mechanics
        "Q178885",
        # astrophysics
        "Q169390",
        # cosmology
        "Q816264",
        # quantum field theory
        "Q11418",
        # string theory
        "Q11457",
        # standard model
        "Q5891",
        # Key physicists
        # Albert Einstein
        "Q937",
        # Niels Bohr
        "Q8963",
        # Richard Feynman
        "Q15092",
        # Marie Curie
        "Q7186",
        # Werner Heisenberg
        "Q7283",
        # Max Planck
        "Q9047",
        # Erwin Schrödinger
        "Q47285",
        # Paul Dirac
        "Q46246",
        # Isaac Newton
        "Q7312",
        # James Clerk Maxwell
        "Q9095",
        # Key experiments/phenomena
        # EPR paradox
        "Q189737",
        # Bell's theorem
        "Q194112",
        # wave-particle duality
        "Q3229",
        # Higgs boson
        "Q133900",
        # black hole
        "Q164800"
      ],
      wikidata_search_queries: [
        "quantum mechanics",
        "general relativity",
        "particle physics",
        "thermodynamics",
        "electromagnetism",
        "astrophysics",
        "condensed matter",
        "nuclear physics",
        "quantum field theory",
        "cosmological model"
      ],
      arxiv_queries: [
        "quantum mechanics foundations",
        "general relativity",
        "particle physics standard model",
        "quantum information theory",
        "condensed matter strongly correlated"
      ],
      estimated_entities: 2500
    }
  end

  def philosophy do
    %{
      name: "philosophy",
      wikidata_root_qids: [
        # philosophy
        "Q5891",
        # epistemology
        "Q7098695",
        # metaphysics
        "Q7257",
        # logic
        "Q9471",
        # ethics
        "Q180684",
        # philosophy of mind
        "Q2200417",
        # philosophy of science
        "Q194253",
        # political philosophy
        "Q1921028",
        # existentialism
        "Q179805",
        # phenomenology
        "Q42965",
        # pragmatism
        "Q333516",
        # empiricism
        "Q178061",
        # rationalism
        "Q189746",
        # utilitarianism
        "Q18336",
        # Key philosophers
        # Aristotle
        "Q868",
        # Plato
        "Q859",
        # René Descartes
        "Q9191",
        # Immanuel Kant
        "Q9312",
        # David Hume
        "Q9252",
        # Ludwig Wittgenstein
        "Q36322",
        # Socrates
        "Q72",
        # John Locke
        "Q5879",
        # Gottfried Wilhelm Leibniz
        "Q9235",
        # Simone de Beauvoir
        "Q155106",
        # Karl Popper
        "Q7241",
        # Thomas Kuhn
        "Q44336",
        # Michel Foucault
        "Q160270"
      ],
      wikidata_search_queries: [
        "epistemology",
        "metaphysics",
        "philosophy of science",
        "philosophy of mind",
        "political philosophy",
        "ethics moral philosophy",
        "phenomenology",
        "existentialism",
        "analytic philosophy",
        "continental philosophy"
      ],
      arxiv_queries: [],
      estimated_entities: 1500
    }
  end

  def mathematics do
    %{
      name: "mathematics",
      wikidata_root_qids: [
        # mathematics
        "Q395",
        # set theory
        "Q12482",
        # number theory
        "Q7754",
        # abstract algebra
        "Q12483",
        # topology
        "Q149972",
        # calculus
        "Q11518",
        # differential equations
        "Q21130",
        # probability theory
        "Q12479",
        # mathematical logic
        "Q12484",
        # graph theory
        "Q181296",
        # combinatorics
        "Q182329",
        # geometry
        "Q23373",
        # algebraic geometry
        "Q273623",
        # numerical analysis
        "Q212108",
        # category theory
        "Q7094",
        # Key mathematicians
        # Leonhard Euler
        "Q7604",
        # Carl Friedrich Gauss
        "Q6722",
        # Emmy Noether
        "Q131761",
        # Alan Turing
        "Q6201",
        # Alexander Grothendieck
        "Q76576",
        # Georg Cantor
        "Q8882",
        # Bernhard Riemann
        "Q153394",
        # David Hilbert
        "Q60008"
      ],
      wikidata_search_queries: [
        "abstract algebra",
        "topology",
        "number theory",
        "graph theory",
        "probability theory",
        "mathematical logic",
        "differential geometry",
        "category theory"
      ],
      arxiv_queries: [
        "algebraic topology",
        "number theory primes",
        "category theory foundations",
        "graph theory algorithms"
      ],
      estimated_entities: 2000
    }
  end

  def computer_science do
    %{
      name: "computer_science",
      wikidata_root_qids: [
        # computer science
        "Q21198",
        # machine learning
        "Q175263",
        # artificial intelligence
        "Q11660",
        # computational complexity
        "Q209187",
        # algorithm design
        "Q741019",
        # cryptography
        "Q80006",
        # distributed computing
        "Q131476",
        # natural language processing
        "Q193692",
        # database
        "Q30642",
        # information theory
        "Q11661",
        # formal language
        "Q188869",
        # neural network
        "Q5482740",
        # deep learning
        "Q1128340",
        # computer vision
        "Q6581258",
        # Key figures
        # Alan Turing
        "Q6201",
        # Claude Shannon
        "Q92604",
        # Donald Knuth
        "Q92743",
        # Tim Berners-Lee
        "Q295875",
        # Geoffrey Hinton
        "Q1397526"
      ],
      wikidata_search_queries: [
        "machine learning",
        "artificial intelligence",
        "computational complexity",
        "cryptography",
        "natural language processing",
        "computer vision",
        "distributed systems",
        "programming language theory"
      ],
      arxiv_queries: [
        "transformer attention mechanism",
        "large language model",
        "reinforcement learning",
        "graph neural network",
        "federated learning"
      ],
      estimated_entities: 2000
    }
  end

  def legal_history do
    %{
      name: "legal_history",
      wikidata_root_qids: [
        # law
        "Q7748",
        # constitutional law
        "Q15719684",
        # international law
        "Q1084573",
        # human rights
        "Q7188",
        # common law
        "Q179234",
        # civil law
        "Q1084",
        # jurisprudence
        "Q43338",
        # natural law
        "Q155076",
        # separation of powers
        "Q82264",
        # rule of law
        "Q7755",
        # habeas corpus
        "Q44918",
        # Magna Carta
        "Q167810",
        # Napoleonic Code
        "Q127751",
        # Key legal thinkers
        # John Rawls
        "Q9353",
        # Hans Kelsen
        "Q310574",
        # H.L.A. Hart
        "Q318100",
        # John Locke
        "Q5879",
        # Montesquieu
        "Q43416"
      ],
      wikidata_search_queries: [
        "constitutional law",
        "international law",
        "human rights law",
        "jurisprudence",
        "legal philosophy",
        "common law history"
      ],
      arxiv_queries: [],
      estimated_entities: 1000
    }
  end

  def political_science do
    %{
      name: "political_science",
      wikidata_root_qids: [
        # politics
        "Q7163",
        # democracy
        "Q7174",
        # authoritarianism
        "Q188961",
        # sovereignty
        "Q162940",
        # political system
        "Q48631",
        # socialism
        "Q11206",
        # liberalism
        "Q6199",
        # capitalism
        "Q11019",
        # communism
        "Q7164",
        # federalism
        "Q15727048",
        # international relations
        "Q465613",
        # political economy
        "Q170156",
        # suffrage
        "Q47043",
        # Key thinkers
        # Karl Marx
        "Q9441",
        # Thomas Hobbes
        "Q5687",
        # Jean-Jacques Rousseau
        "Q9381",
        # Hannah Arendt
        "Q320052"
      ],
      wikidata_search_queries: [
        "political system",
        "international relations",
        "political economy",
        "democratic theory",
        "political philosophy"
      ],
      arxiv_queries: [],
      estimated_entities: 1000
    }
  end
end
