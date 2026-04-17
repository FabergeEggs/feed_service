defmodule FeedService.Repo do
  use Ecto.Repo,
    otp_app: :feed_service,
    adapter: Ecto.Adapters.Postgres
end
