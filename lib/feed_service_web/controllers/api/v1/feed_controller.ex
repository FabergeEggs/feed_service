defmodule FeedServiceWeb.Api.V1.FeedController do
  use FeedServiceWeb, :controller

  alias FeedService.Feed

  @doc "GET /api/v1/feed — current user's personal timeline."
  def index(conn, params) do
    user_id = conn.assigns.current_user.id
    opts = build_opts(params)

    case Feed.list_user_timeline(user_id, opts) do
      {:ok, page} ->
        render(conn, :page, page: page)

      {:error, :invalid_cursor} ->
        send_error(conn, 400, "invalid_cursor")
    end
  end

  @doc "GET /api/v1/feed/projects/:project_id — timeline for one project."
  def project_feed(conn, %{"project_id" => project_id} = params) do
    case Ecto.UUID.cast(project_id) do
      {:ok, _} ->
        case Feed.list_project_feed(project_id, build_opts(params)) do
          {:ok, page} -> render(conn, :page, page: page)
          {:error, :invalid_cursor} -> send_error(conn, 400, "invalid_cursor")
        end

      :error ->
        send_error(conn, 400, "invalid_project_id")
    end
  end

  defp build_opts(params) do
    [cursor: params["cursor"], limit: parse_int(params["limit"])]
  end

  defp parse_int(nil), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp send_error(conn, status, code) do
    conn
    |> put_status(status)
    |> json(%{error: code})
  end
end
