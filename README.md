# Palimpedia

A generative epistemic network — documents that know their position.

Palimpedia is a living knowledge graph where documents are not written by humans and stored, but inferred from structural necessity and generated on demand. Where Wikipedia asks "what do people want to record," Palimpedia asks "what does the graph require to be coherent."

## Architecture

Five interdependent layers:

| Layer | Name | Role |
|-------|------|------|
| 0 | **Anchor Corpus** | Verified external sources (Wikidata, arXiv, legal DBs). The only non-generated layer. |
| 1 | **Graph Substrate** | Neo4j property graph. Nodes = documents, edges = typed relationships. Single source of truth. |
| 2 | **Gap Detection Engine** | Structural hole detection, orphan resolution, asymmetric coverage analysis. Feeds the generation queue. |
| 3 | **Generation Pipeline** | LLM-powered document generation from subgraph context. Outputs include confidence scores and provenance chains. |
| 4 | **User Interface & API** | REST/GraphQL API, crawler surface, three-tier user interaction model. |

## User Interaction Tiers

1. **Node Request** (Low Trust) — "Generate a document about X"
2. **Edge Assertion** (Medium Trust) — "X connects to Y via mechanism Z"
3. **Contradiction Flag** (High Trust) — "Document A is inconsistent with Document B"

## Tech Stack

- **Elixir / Phoenix** — API server, background processing
- **Neo4j** — Property graph database
- **Oban** — Background job queue (gap detection, generation)
- **Absinthe** — GraphQL API
- **Anthropic Claude** — Document generation

## Getting Started

### Prerequisites

- Elixir 1.15+
- Neo4j 5.x (or use Docker: `docker run -p 7474:7474 -p 7687:7687 neo4j:5`)
- Set environment variables:
  ```bash
  export NEO4J_URL=bolt://localhost:7687
  export NEO4J_USERNAME=neo4j
  export NEO4J_PASSWORD=your_password
  export ANTHROPIC_API_KEY=your_key
  ```

### Setup

```bash
mix deps.get
mix phx.server
```

### API Endpoints

```bash
# Retrieve a document node
curl http://localhost:4000/api/nodes/:id

# Search nodes
curl http://localhost:4000/api/nodes/search?q=quantum

# Request a new document (Tier 1)
curl -X POST http://localhost:4000/api/nodes/request \
  -H "Content-Type: application/json" \
  -d '{"title": "Quantum Entanglement and Bell Inequalities"}'

# Assert an edge (Tier 2)
curl -X POST http://localhost:4000/api/edges \
  -H "Content-Type: application/json" \
  -d '{"source": "Bell Theorem", "target": "EPR Paradox", "relationship": "contradicts"}'

# Flag a contradiction (Tier 3)
curl -X POST http://localhost:4000/api/contradictions \
  -H "Content-Type: application/json" \
  -d '{"node_a_id": "abc123", "node_b_id": "def456", "description": "Conflicting dates"}'

# Graph stats
curl http://localhost:4000/api/graph/stats

# Structural gaps
curl http://localhost:4000/api/graph/gaps
```

## Development Roadmap

See [GitHub Issues](../../issues) for the full roadmap organized by milestone.

## License

MIT
