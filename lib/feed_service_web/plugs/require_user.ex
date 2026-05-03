defmodule FeedServiceWeb.Plugs.RequireUser do
  @moduledoc """
  Halts the request with 401 when `conn.assigns.current_user` is missing.
  Must run after `UserContext`.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      %{id: id} when is_binary(id) ->
        conn

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, ~s({"error":"unauthenticated"}))
        |> halt()
    end
  end
end
