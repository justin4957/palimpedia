import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :palimpedia, PalimpediaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "71vFm46JndOLhggLIdjiFTwbqpFy+2HW5FMKSYW/kZTeOQgCgGkd1lb93I+j5Osq",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
