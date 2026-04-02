defmodule PalimpediaWeb.Router do
  use PalimpediaWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug PalimpediaWeb.Plugs.RateLimiter, max_requests: 60, window_ms: 60_000
  end

  pipeline :crawler do
    plug :accepts, ["xml"]
  end

  # Sitemap for search engines
  scope "/", PalimpediaWeb do
    pipe_through :crawler
    get "/sitemap.xml", SitemapController, :index
  end

  # HTML graph explorer
  scope "/explore", PalimpediaWeb do
    pipe_through :browser

    get "/", ExplorerController, :index
    get "/random", ExplorerController, :random
    get "/nodes/:id", ExplorerController, :show_node
  end

  # GraphQL endpoint for researcher access
  scope "/graphql" do
    pipe_through :api

    forward "/", Absinthe.Plug, schema: PalimpediaWeb.GraphQL.Schema
  end

  scope "/api", PalimpediaWeb do
    pipe_through :api

    # Layer 4: Document nodes
    get "/nodes/search", NodeController, :search
    get "/nodes/:id", NodeController, :show
    post "/nodes/request", NodeController, :request_node

    # User trust & convergence
    get "/users/:user_id/trust", NodeController, :user_trust
    get "/convergence", ConvergenceController, :index
    get "/convergence/stats", ConvergenceController, :stats

    # Domain configuration
    get "/domains", DomainController, :index
    get "/domains/:id", DomainController, :show
    get "/domains/:id/edge-types", DomainController, :edge_types

    # Security monitoring
    get "/security/stats", SecurityController, :stats
    get "/security/blocks", SecurityController, :recent_blocks

    # On-demand generation
    get "/generate/evaluate", OnDemandController, :evaluate
    get "/generate/status", OnDemandController, :status
    get "/generate/pending", OnDemandController, :list_pending

    # Provenance explorer
    get "/provenance/trace/:node_id", ProvenanceController, :trace
    get "/provenance/audit", ProvenanceController, :audit
    get "/provenance/broken-chains", ProvenanceController, :broken_chains

    # Revision history
    get "/revisions/recent", RevisionController, :recent
    get "/revisions/stats", RevisionController, :stats
    get "/revisions/node/:node_id", RevisionController, :history_for

    # Layer 4: Edge assertions
    post "/edges", NodeController, :assert_edge

    # Layer 4: Contradiction flags
    post "/contradictions", NodeController, :flag_contradiction

    # Human review queue
    get "/reviews", ReviewController, :index
    get "/reviews/stats", ReviewController, :stats
    get "/reviews/:id", ReviewController, :show
    post "/reviews/:id/approve", ReviewController, :approve
    post "/reviews/:id/reject", ReviewController, :reject
    post "/reviews/:id/flag", ReviewController, :flag

    # Coverage map & epistemic index
    get "/coverage", CoverageController, :index
    get "/coverage/density", CoverageController, :density
    get "/coverage/confidence", CoverageController, :confidence
    get "/coverage/blind-spots", CoverageController, :blind_spots
    get "/coverage/gaps", CoverageController, :gaps
    get "/coverage/epistemic-index", CoverageController, :epistemic_index

    # Federation
    get "/federation/peers", FederationController, :list_peers
    post "/federation/peers", FederationController, :register_peer
    post "/federation/export/:node_id", FederationController, :export
    post "/federation/import", FederationController, :import_message
    get "/federation/conflicts", FederationController, :list_conflicts
    get "/federation/conflicts/stats", FederationController, :conflict_stats
    post "/federation/conflicts/:id/resolve", FederationController, :resolve_conflict

    # Graph operations
    get "/graph/subgraph/:id", GraphController, :subgraph
    get "/graph/stats", GraphController, :stats
    get "/graph/gaps", GraphController, :gaps
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:palimpedia, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: PalimpediaWeb.Telemetry
    end
  end
end
