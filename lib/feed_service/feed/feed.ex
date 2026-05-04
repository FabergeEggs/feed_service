defmodule FeedService.Feed do
  @moduledoc "Read/write API for the timeline."

  import Ecto.Query

  alias FeedService.Repo
  alias FeedService.Feed.{FeedItem, Subscription, Membership, Profile, Cursor}

  @default_limit 20
  @max_limit 100

  def list_user_timeline(user_id, opts \\ []) do
    limit = clamp_limit(opts[:limit])

    case Cursor.decode(opts[:cursor]) do
      :error ->
        {:error, :invalid_cursor}

      {:ok, point} ->
        items =
          FeedItem
          |> where(^user_timeline_where(user_id))
          |> apply_cursor(point)
          |> order_by([i], desc: i.occurred_at, desc: i.id)
          |> limit(^limit)
          |> Repo.all()

        {:ok, %{items: items, next_cursor: next_cursor(items, limit)}}
    end
  end

  defp user_timeline_where(user_id) do
    project_subs =
      from s in Subscription,
        where: s.user_id == ^user_id and s.target_type == "project",
        select: s.target_id

    member_projects =
      from m in Membership,
        where: m.user_id == ^user_id,
        select: m.project_id

    user_subs =
      from s in Subscription,
        where: s.user_id == ^user_id and s.target_type == "user",
        select: s.target_id

    dynamic(
      [i],
      i.project_id in subquery(project_subs) or
        i.project_id in subquery(member_projects) or
        i.actor_id in subquery(user_subs)
    )
  end

  def list_project_feed(project_id, opts \\ []) do
    limit = clamp_limit(opts[:limit])

    case Cursor.decode(opts[:cursor]) do
      :error ->
        {:error, :invalid_cursor}

      {:ok, point} ->
        items =
          FeedItem
          |> where([i], i.project_id == ^project_id)
          |> apply_cursor(point)
          |> order_by([i], desc: i.occurred_at, desc: i.id)
          |> limit(^limit)
          |> Repo.all()

        {:ok, %{items: items, next_cursor: next_cursor(items, limit)}}
    end
  end

  def upsert_item(attrs) do
    case %FeedItem{} |> FeedItem.changeset(attrs) |> Repo.insert() do
      {:ok, item} ->
        {:ok, item}

      {:error, changeset} ->
        if duplicate_event?(changeset) do
          {:ok, :duplicate}
        else
          {:error, changeset}
        end
    end
  end

  def delete_by_source(source_type, source_id) do
    {count, _} =
      FeedItem
      |> where([i], i.source_type == ^source_type and i.source_id == ^source_id)
      |> Repo.delete_all()

    count
  end

  def get_item(id), do: Repo.get(FeedItem, id)

  def subscribe(user_id, target_type, target_id) do
    attrs = %{user_id: user_id, target_type: target_type, target_id: target_id}

    case %Subscription{} |> Subscription.changeset(attrs) |> Repo.insert() do
      {:ok, sub} ->
        {:ok, sub}

      {:error, changeset} ->
        if duplicate_subscription?(changeset) do
          {:ok, get_subscription(user_id, target_type, target_id)}
        else
          {:error, changeset}
        end
    end
  end

  def unsubscribe(user_id, target_type, target_id) do
    Subscription
    |> where(
      [s],
      s.user_id == ^user_id and s.target_type == ^target_type and s.target_id == ^target_id
    )
    |> Repo.delete_all()

    :ok
  end

  def list_subscriptions(user_id) do
    Subscription
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  def unsubscribe_by_id(user_id, subscription_id) do
    Subscription
    |> where([s], s.id == ^subscription_id and s.user_id == ^user_id)
    |> Repo.delete_all()

    :ok
  end

  def upsert_membership(attrs) do
    %Membership{}
    |> Membership.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:role, :joined_at, :updated_at]},
      conflict_target: [:user_id, :project_id],
      # `returning: true` keeps `m.id` consistent with the row in DB on conflict.
      returning: true
    )
  end

  def remove_membership(user_id, project_id) do
    Membership
    |> where([m], m.user_id == ^user_id and m.project_id == ^project_id)
    |> Repo.delete_all()

    :ok
  end

  def upsert_profile(attrs) do
    %Profile{}
    |> Profile.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:name, :avatar_url, :updated_at]},
      conflict_target: :user_id
    )
  end

  def lookup_profile(user_id), do: Repo.get(Profile, user_id)

  defp clamp_limit(nil), do: @default_limit
  defp clamp_limit(n) when is_integer(n) and n > 0, do: min(n, @max_limit)
  defp clamp_limit(_), do: @default_limit

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, {at, id}) do
    where(
      query,
      [i],
      fragment(
        "(?, ?) < (?, ?)",
        i.occurred_at,
        i.id,
        type(^at, :utc_datetime_usec),
        type(^id, :binary_id)
      )
    )
  end

  defp next_cursor(items, limit) when length(items) < limit, do: nil

  defp next_cursor(items, _limit) do
    last = List.last(items)
    Cursor.encode({last.occurred_at, last.id})
  end

  defp get_subscription(user_id, target_type, target_id) do
    Repo.get_by(Subscription,
      user_id: user_id,
      target_type: target_type,
      target_id: target_id
    )
  end

  defp duplicate_event?(%Ecto.Changeset{errors: errors}) do
    match?({_, [{:constraint, :unique} | _]}, errors[:event_id])
  end

  defp duplicate_subscription?(%Ecto.Changeset{errors: errors}) do
    match?({_, [{:constraint, :unique} | _]}, errors[:user_id])
  end
end
