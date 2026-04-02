defmodule Palimpedia.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PalimpediaWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:palimpedia, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Palimpedia.PubSub},
      {Bolt.Sips, Application.get_env(:bolt_sips, Bolt)},
      Palimpedia.Interaction.UserTrust,
      Palimpedia.Interaction.Convergence,
      Palimpedia.Confidence.Contradiction,
      Palimpedia.Review.Queue,
      Palimpedia.GapDetection.GenerationQueue,
      Palimpedia.Generation.OnDemand,
      Palimpedia.Generation.Metrics,
      Palimpedia.GapDetection.Scheduler,
      Palimpedia.Generation.BatchWorker,
      PalimpediaWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Palimpedia.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PalimpediaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
