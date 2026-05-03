defmodule FeedServiceWeb.Router do
  use FeedServiceWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug FeedServiceWeb.Plugs.UserContext
  end

  pipeline :authenticated do
    plug FeedServiceWeb.Plugs.RequireUser
  end

  scope "/api/v1", FeedServiceWeb.Api.V1 do
    pipe_through :api

    get "/health", HealthController, :show

    scope "/" do
      pipe_through :authenticated

      get "/feed", FeedController, :index
      get "/feed/projects/:project_id", FeedController, :project_feed

      get "/subscriptions", SubscriptionController, :index
      post "/subscriptions", SubscriptionController, :create
      delete "/subscriptions/:id", SubscriptionController, :delete
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:feed_service, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: FeedServiceWeb.Telemetry
    end
  end
end
