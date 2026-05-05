import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :feed_service, FeedService.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "feed_service_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :feed_service, FeedServiceWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "tqa7P6sxWy6n/0qlBRd6pS08FKLtlPfN3cXzTYMPSf2IeX3wEBTFxxvoAv5Oh8K5",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Mox-generated stub for the ProfileClient behaviour.
config :feed_service, :profile_client_impl, FeedService.Clients.ProfileClientMock

# Disable Redis-backed cache — tests stub it through Mox or just don't set it.
config :feed_service, :redis, url: "redis://localhost:6379/15"
