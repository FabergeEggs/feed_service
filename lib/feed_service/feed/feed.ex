defmodule FeedService.Feed do
  @moduledoc """
  Public API for the feed timeline.

  Grown step by step. Currently exposes project-scoped read and the
  basic write helpers used by event handlers. User-scoped timeline,
  subscriptions, and memberships come in later steps.
  """

  import Ecto.Query

  alias FeedService.Repo
  alias FeedService.Feed.{FeedItem, Subscription, Membership, Profile, Cursor}

  @default_limit 20
  @max_limit 100

  @doc """
  Returns one page of a user's personal timeline, newest first.

  Includes feed items where:
    * the project is in the user's subscriptions (`target_type: "project"`)
    * the project is in the user's memberships (implicit follow)
    * the actor is in the user's user-subscriptions (`target_type: "user"`)

  Same `:cursor`/`:limit` semantics as `list_project_feed/2`.
  """
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

  # Builds the dynamic WHERE clause that filters feed_items by the
  # user's subscriptions and memberships. Three small subqueries are
  # combined with OR.
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

  @doc """
  Returns one page of feed items for a single project, newest first.

  ## Options

    * `:cursor` — opaque cursor returned by a previous call (or `nil`)
    * `:limit`  — page size, default `#{@default_limit}`, capped at `#{@max_limit}`

  ## Return value

    * `{:ok, %{items: [%FeedItem{}, ...], next_cursor: cursor | nil}}`
    * `{:error, :invalid_cursor}` if the cursor failed to decode
  """
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

  @doc """
  Inserts a feed item, ignoring re-deliveries with the same `event_id`.

  Returns:
    * `{:ok, %FeedItem{}}` — newly inserted row
    * `{:ok, :duplicate}`  — same `event_id` was already there
    * `{:error, changeset}` — validation failed
  """
  def upsert_item(attrs) do
    case %FeedItem{} |> FeedItem.changeset(attrs) |> Repo.insert() do
      {:ok, item} ->
        {:ok, item}

      {:error, changeset} ->
        # `unique_constraint(:event_id)` in the schema turns a Postgres
        # unique-violation into a changeset error of shape
        # `{"has already been taken", [constraint: :unique, ...]}`.
        # Anything else is a real validation failure and must propagate.
        if duplicate_event?(changeset) do
          {:ok, :duplicate}
        else
          {:error, changeset}
        end
    end
  end

  defp duplicate_event?(%Ecto.Changeset{errors: errors}) do
    match?({_, [{:constraint, :unique} | _]}, errors[:event_id])
  end

  @doc """
  Removes every feed_item that projects the given upstream entity.
  Used on `*.deleted` events. Returns the number of rows removed.
  """
  def delete_by_source(source_type, source_id) do
    {count, _} =
      FeedItem
      |> where([i], i.source_type == ^source_type and i.source_id == ^source_id)
      |> Repo.delete_all()

    count
  end

  @doc "Fetches a feed_item by its primary key, or `nil`."
  def get_item(id), do: Repo.get(FeedItem, id)

  # ── Subscriptions ────────────────────────────────────────────────────

  @doc """
  Subscribes a user to a target. Idempotent — calling twice with the
  same triple returns the existing subscription, not an error.

  Returns `{:ok, %Subscription{}}` on success, `{:error, changeset}` on
  validation failure (e.g. unknown `target_type`).
  """
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

  @doc """
  Removes a subscription. Idempotent — succeeds even if the row was
  already gone or never existed.
  """
  def unsubscribe(user_id, target_type, target_id) do
    Subscription
    |> where(
      [s],
      s.user_id == ^user_id and s.target_type == ^target_type and s.target_id == ^target_id
    )
    |> Repo.delete_all()

    :ok
  end

  @doc "Lists every subscription of a user, newest first."
  def list_subscriptions(user_id) do
    Subscription
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Removes a subscription by its primary key — but only if it belongs to
  the given user. Idempotent. Used by `DELETE /subscriptions/:id`.
  """
  def unsubscribe_by_id(user_id, subscription_id) do
    Subscription
    |> where([s], s.id == ^subscription_id and s.user_id == ^user_id)
    |> Repo.delete_all()

    :ok
  end

  defp get_subscription(user_id, target_type, target_id) do
    Repo.get_by(Subscription,
      user_id: user_id,
      target_type: target_type,
      target_id: target_id
    )
  end

  defp duplicate_subscription?(%Ecto.Changeset{errors: errors}) do
    # The unique index covers (user_id, target_type, target_id).
    # `unique_constraint/2` puts the resulting error on the first listed
    # field — `:user_id` here.
    match?({_, [{:constraint, :unique} | _]}, errors[:user_id])
  end

  # ── Memberships ──────────────────────────────────────────────────────

  @doc """
  Inserts or updates a project membership. Idempotent: if the same
  `(user_id, project_id)` pair exists, role and joined_at are replaced
  with the new values (Postgres `ON CONFLICT DO UPDATE`).
  """
  def upsert_membership(attrs) do
    %Membership{}
    |> Membership.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:role, :joined_at, :updated_at]},
      conflict_target: [:user_id, :project_id],
      # Without `returning`, the returned struct keeps the client-side
      # UUID even when Postgres updated the existing row → callers that
      # take `m.id` and do `Repo.get(Membership, id)` would see `nil`.
      returning: true
    )
  end

  @doc "Removes a membership. Idempotent — returns `:ok` even if missing."
  def remove_membership(user_id, project_id) do
    Membership
    |> where([m], m.user_id == ^user_id and m.project_id == ^project_id)
    |> Repo.delete_all()

    :ok
  end

  # ── Profile cache ────────────────────────────────────────────────────

  @doc """
  Inserts or updates a denormalized profile row. Used both by event
  handlers and by lazy REST fetches when the cache misses.
  """
  def upsert_profile(attrs) do
    %Profile{}
    |> Profile.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:name, :avatar_url, :updated_at]},
      conflict_target: :user_id
    )
  end

  @doc "Reads a cached profile row, or `nil`."
  def lookup_profile(user_id), do: Repo.get(Profile, user_id)

  defp clamp_limit(nil), do: @default_limit
  defp clamp_limit(n) when is_integer(n) and n > 0, do: min(n, @max_limit)
  defp clamp_limit(_), do: @default_limit

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, {at, id}) do
    # `type/2` tells Ecto to encode the pinned values with the right
    # column types — without it Postgrex sees raw strings and refuses
    # to send a 36-char UUID into a `uuid` column.
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

  # Page is shorter than `limit` ⇒ no more rows after this batch.
  defp next_cursor(items, limit) when length(items) < limit, do: nil

  defp next_cursor(items, _limit) do
    last = List.last(items)
    Cursor.encode({last.occurred_at, last.id})
  end
end
