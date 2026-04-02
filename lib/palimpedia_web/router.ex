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

  scope "/api", PalimpediaWeb do
    pipe_through :api

    # Layer 4: Document nodes
    get "/nodes/search", NodeController, :search
    get "/nodes/:id", NodeController, :show
    post "/nodes/request", NodeController, :request_node

    # On-demand generation
    get "/generate/evaluate", OnDemandController, :evaluate
    get "/generate/status", OnDemandController, :status
    get "/generate/pending", OnDemandController, :list_pending

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
