import Config

config :feed_service,
  ecto_repos: [FeedService.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :feed_service, FeedServiceWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: FeedServiceWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FeedService.PubSub,
  live_view: [signing_salt: "J5NaMHOA"]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

# Compile-time defaults; real values come from dev.exs/test.exs or runtime.exs env.
config :feed_service, :redis, url: nil
config :feed_service, :kafka, brokers: [], group_id: "feed-service"
config :feed_service, :media_client, base_url: nil, token: nil
config :feed_service, :project_client, base_url: nil
config :feed_service, :profile_client, base_url: nil

import_config "#{config_env()}.exs"
