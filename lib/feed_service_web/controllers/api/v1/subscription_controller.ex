defmodule FeedServiceWeb.Api.V1.SubscriptionController do
  use FeedServiceWeb, :controller

  alias FeedService.Feed

  @doc "GET /api/v1/subscriptions — list current user's subscriptions."
  def index(conn, _params) do
    subs = Feed.list_subscriptions(conn.assigns.current_user.id)
    render(conn, :index, subscriptions: subs)
  end

  @doc "POST /api/v1/subscriptions — body: {target_type, target_id}."
  def create(conn, %{"target_type" => target_type, "target_id" => target_id}) do
    user_id = conn.assigns.current_user.id

    case Feed.subscribe(user_id, target_type, target_id) do
      {:ok, sub} ->
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

  @doc "DELETE /api/v1/subscriptions/:id — idempotent."
  def delete(conn, %{"id" => id}) do
    case Ecto.UUID.cast(id) do
      {:ok, _} ->
        Feed.unsubscribe_by_id(conn.assigns.current_user.id, id)
        send_resp(conn, :no_content, "")

      :error ->
        # Malformed UUID — treat the same as "doesn't exist".
        # No information leak, no exception.
        send_resp(conn, :no_content, "")
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
