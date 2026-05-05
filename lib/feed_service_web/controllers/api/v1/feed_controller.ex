defmodule FeedServiceWeb.Api.V1.FeedController do
  use FeedServiceWeb, :controller

  alias FeedService.{Cache, Feed}
  alias FeedService.Feed.MediaEnrichment

  @cache_ttl 30

  def index(conn, params) do
    user_id = conn.assigns.current_user.id
    opts = build_opts(params)
    key = "feed:user:#{user_id}:cur:#{opts[:cursor] || "_"}:lim:#{opts[:limit] || "_"}"

    serve_page(conn, key, fn -> Feed.list_user_timeline(user_id, opts) end)
  end

  def project_feed(conn, %{"project_id" => project_id} = params) do
    case Ecto.UUID.cast(project_id) do
      {:ok, _} ->
        opts = build_opts(params)
        key = "feed:project:#{project_id}:cur:#{opts[:cursor] || "_"}:lim:#{opts[:limit] || "_"}"

        serve_page(conn, key, fn -> Feed.list_project_feed(project_id, opts) end)

      :error ->
        send_error(conn, 400, "invalid_project_id")
    end
  end

  defp serve_page(conn, cache_key, fetch_fn) do
    case Cache.get(cache_key) do
      {:ok, page} ->
        render_page(conn, page)

      _ ->
        case fetch_fn.() do
          {:ok, page} ->
            Cache.put(cache_key, page, @cache_ttl)
            render_page(conn, page)

          {:error, :invalid_cursor} ->
            send_error(conn, 400, "invalid_cursor")
        end
    end
  end

  defp render_page(conn, page) do
    media = MediaEnrichment.for_items(page.items)
    render(conn, :page, page: page, media: media)
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
