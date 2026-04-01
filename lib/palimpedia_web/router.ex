defmodule PalimpediaWeb.Router do
  use PalimpediaWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", PalimpediaWeb do
    pipe_through :api

    # Layer 4: Document nodes
    get "/nodes/search", NodeController, :search
    get "/nodes/:id", NodeController, :show
    post "/nodes/request", NodeController, :request_node

    # Layer 4: Edge assertions
    post "/edges", NodeController, :assert_edge

    # Layer 4: Contradiction flags
    post "/contradictions", NodeController, :flag_contradiction

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
