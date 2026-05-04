defmodule FeedServiceWeb.Plugs.UserContext do
  @moduledoc "Reads X-User-* headers (set by gateway) into `conn.assigns.current_user`."

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
