defmodule FeedServiceWeb.Plugs.UserContext do
  @moduledoc """
  Reads `X-User-Id`, `X-Username`, `X-User-Roles` request headers (set by
  the API gateway after JWT validation) and attaches the user to
  `conn.assigns.current_user`.

  Soft plug: missing headers don't fail the request — public endpoints
  like `/health` keep working. Use `RequireUser` afterwards for
  authenticated routes.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case header(conn, "x-user-id") do
      id when is_binary(id) and id != "" ->
        assign(conn, :current_user, %{
          id: id,
          name: header(conn, "x-username"),
          roles: parse_roles(header(conn, "x-user-roles"))
        })

      _ ->
        conn
    end
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [v | _] -> v
      [] -> nil
    end
  end

  defp parse_roles(nil), do: []
  defp parse_roles(""), do: []

  defp parse_roles(csv) when is_binary(csv) do
    csv
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
