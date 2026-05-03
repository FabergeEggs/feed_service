# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :feed_service,
  ecto_repos: [FeedService.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :feed_service, FeedServiceWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: FeedServiceWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FeedService.PubSub,
  live_view: [signing_salt: "J5NaMHOA"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Compile-time defaults for runtime-loaded settings. Real values are
# overridden in `dev.exs` / `test.exs` and `runtime.exs` (env vars).
config :feed_service, :redis, url: nil

config :feed_service, :kafka,
  brokers: [],
  group_id: "feed-service",
  topics: %{
    project_events: "project-events",
    response_added: "response_service.response.add",
    response_deleted: "response_service.response.delete",
    profile_changed: "profile_service.profile.changed"
  }

config :feed_service, :media_client, base_url: nil, token: nil
config :feed_service, :project_client, base_url: nil
config :feed_service, :profile_client, base_url: nil

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
