defmodule FeedServiceWeb.Api.V1.HealthController do
  use FeedServiceWeb, :controller

  @doc "Liveness probe — always succeeds while the BEAM is up."
  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
