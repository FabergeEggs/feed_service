import Config

config :feed_service, FeedService.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "feed_service_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :feed_service, FeedServiceWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "Sgt9H/TFKx01E440+d+MzepoQc+WsHmf/l2njsCgCwCun8hqYFxL4KSw/cWuxsnT",
  watchers: []

config :feed_service, dev_routes: true

config :feed_service, :redis, url: "redis://localhost:6379/0"
# Empty by default — Broadway stays disabled. Set KAFKA_BROKERS to enable.
config :feed_service, :kafka, brokers: []
config :feed_service, :media_client, base_url: "http://localhost:4001", token: "dev-feed-token"
config :feed_service, :project_client, base_url: "http://localhost:8000"
config :feed_service, :profile_client, base_url: "http://localhost:8003"

config :logger, :default_formatter, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
