defmodule FeedServiceWeb.Api.V1.FeedController do
  use FeedServiceWeb, :controller

  alias FeedService.{Cache, Feed}
  alias FeedService.Feed.MediaEnrichment
  alias FeedService.Clients.ProjectClient

  @cache_ttl 30
  @memberships_ttl 60

  def global_feed(conn, params) do
    project_ids =
      with %{id: user_id} <- conn.assigns[:current_user],
           "mine" <- params["filter"] do
        resolve_project_ids(user_id)
      else
        _ -> nil
      end

    opts = build_opts(params) ++ [project_ids: project_ids]

    uid_tag = if is_list(project_ids), do: conn.assigns.current_user.id, else: "_"
    key = "feed:global:u:#{uid_tag}:cur:#{opts[:cursor] || "_"}:lim:#{opts[:limit] || "_"}"

    serve_page(conn, key, fn -> Feed.list_global_feed(opts) end)
  end

  # Fetch the list of project IDs the user is a member of.
  # Result is cached in Redis for @memberships_ttl seconds to avoid
  # hitting project_service on every feed request.
  defp resolve_project_ids(user_id) do
    cache_key = "memberships:#{user_id}"

    case Cache.get(cache_key) do
      {:ok, ids} ->
        ids

      _ ->
        case ProjectClient.get_user_memberships(user_id) do
          {:ok, body} ->
            ids =
              (body["scientist"] || []) ++ (body["volunteer"] || [])
              |> Enum.map(& &1["project_id"])
              |> Enum.reject(&is_nil/1)
              |> Enum.uniq()

            Cache.put(cache_key, ids, @memberships_ttl)
            ids

          {:error, _} ->
            # project_service unavailable — degrade to unfiltered feed
            nil
        end
    end
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
