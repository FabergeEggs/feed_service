defmodule FeedServiceWeb.Api.V1.HealthController do
  use FeedServiceWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
