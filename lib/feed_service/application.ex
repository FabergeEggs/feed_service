defmodule FeedService.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FeedServiceWeb.Telemetry,
      FeedService.Repo,
      {DNSCluster, query: Application.get_env(:feed_service, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FeedService.PubSub},
      # Start a worker by calling: FeedService.Worker.start_link(arg)
      # {FeedService.Worker, arg},
      # Start to serve requests, typically the last entry
      FeedServiceWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FeedService.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FeedServiceWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
