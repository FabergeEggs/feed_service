defmodule FeedServiceWeb.Api.V1.SubscriptionController do
  use FeedServiceWeb, :controller

  alias FeedService.{Cache, Feed}

  def index(conn, _params) do
    subs = Feed.list_subscriptions(conn.assigns.current_user.id)
    render(conn, :index, subscriptions: subs)
  end

  def create(conn, %{"target_type" => target_type, "target_id" => target_id}) do
    user_id = conn.assigns.current_user.id

    case Feed.subscribe(user_id, target_type, target_id) do
      {:ok, sub} ->
        invalidate_user_feed(user_id)

        conn
        |> put_status(:created)
        |> render(:show, subscription: sub)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_target_type_or_target_id"})
  end

  def delete(conn, %{"id" => id}) do
    user_id = conn.assigns.current_user.id

    case Ecto.UUID.cast(id) do
      {:ok, _} ->
        Feed.unsubscribe_by_id(user_id, id)
        invalidate_user_feed(user_id)
        send_resp(conn, :no_content, "")

      :error ->
        send_resp(conn, :no_content, "")
    end
  end

  defp invalidate_user_feed(user_id) do
    Cache.invalidate_pattern("feed:user:#{user_id}:*")
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
