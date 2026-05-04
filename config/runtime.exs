import Config

if System.get_env("PHX_SERVER") do
  config :feed_service, FeedServiceWeb.Endpoint, server: true
end

config :feed_service, FeedServiceWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if redis_url = System.get_env("REDIS_URL") do
  config :feed_service, :redis, url: redis_url
end

if brokers = System.get_env("KAFKA_BROKERS") do
  parsed =
    brokers
    |> String.split(",", trim: true)
    |> Enum.map(fn pair ->
      [host, port] = String.split(pair, ":", parts: 2)
      {String.trim(host), String.to_integer(String.trim(port))}
    end)

  config :feed_service, :kafka, brokers: parsed
end

if group = System.get_env("KAFKA_GROUP_ID") do
  config :feed_service, :kafka, group_id: group
end

if media_url = System.get_env("MEDIA_SERVICE_URL") do
  config :feed_service, :media_client,
    base_url: media_url,
    token: System.get_env("MEDIA_SERVICE_TOKEN")
end

if project_url = System.get_env("PROJECT_SERVICE_URL") do
  config :feed_service, :project_client, base_url: project_url
end

if profile_url = System.get_env("PROFILE_SERVICE_URL") do
  config :feed_service, :profile_client, base_url: profile_url
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "environment variable DATABASE_URL is missing (ecto://USER:PASS@HOST/DATABASE)"

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :feed_service, FeedService.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "environment variable SECRET_KEY_BASE is missing (run `mix phx.gen.secret`)"

  host = System.get_env("PHX_HOST") || "example.com"

  config :feed_service, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :feed_service, FeedServiceWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base
end
