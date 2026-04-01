# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :palimpedia,
  generators: [timestamp_type: :utc_datetime],
  graph_repository: Palimpedia.Graph.Neo4jRepository

# Neo4j graph database (overridden per environment)
config :bolt_sips, Bolt,
  url: "bolt://localhost:7687",
  basic_auth: [username: "neo4j", password: "palimpedia_dev"],
  pool_size: 10,
  timeout: 15_000

# LLM generation config (API keys loaded from environment)
config :palimpedia, Palimpedia.Generation,
  provider: :anthropic,
  model: "claude-haiku-4-5-20251001",
  max_tokens: 4096

# Configures the endpoint
config :palimpedia, PalimpediaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: PalimpediaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Palimpedia.PubSub,
  live_view: [signing_salt: "E/bB5Kkq"]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
