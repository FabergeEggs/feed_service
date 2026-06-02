defmodule FeedService.Feed do
  @moduledoc "Read/write API for the timeline."

  import Ecto.Query

  alias FeedService.Repo
  # Membership schema kept for upsert_membership/remove_membership
  # (populated by Kafka if project_service adds member events later).
  alias FeedService.Feed.{FeedItem, Membership, Profile, Cursor}

  @default_limit 20
  @max_limit 100

  @doc """
  Returns the global feed, newest first.

  Options:
    - `:cursor`      — opaque pagination cursor
    - `:limit`       — max items (default #{@default_limit}, max #{@max_limit})
    - `:project_ids` — when present, restricts feed to those projects only
                       (caller resolves user memberships via REST)
  """
  def list_global_feed(opts \\ []) do
    limit = clamp_limit(opts[:limit])

    case Cursor.decode(opts[:cursor]) do
      :error ->
        {:error, :invalid_cursor}

      {:ok, point} ->
        items =
          FeedItem
          |> filter_by_membership(opts[:project_ids])
          |> apply_cursor(point)
          |> order_by([i], desc: i.occurred_at, desc: i.id)
          |> limit(^limit)
          |> Repo.all()
          |> enrich_avatars()

        {:ok, %{items: items, next_cursor: next_cursor(items, limit)}}
    end
  end

  # No project_ids → unfiltered global feed.
  defp filter_by_membership(query, nil), do: query
  defp filter_by_membership(query, []), do: where(query, false)

  # project_ids list → restrict feed to those projects only.
  defp filter_by_membership(query, project_ids) when is_list(project_ids) do
    where(query, [i], i.project_id in ^project_ids)
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
          |> enrich_avatars()

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

  @doc """
  Applies a partial update to an existing `profiles_cache` row.
  Only updates fields present in `changes` (non-nil), so a name-only event
  never overwrites `avatar_url` and vice versa.
  Does nothing if the user is not yet in the cache — ProfileEnricher will
  insert a full row on the next REST fetch.
  """
  def patch_cached_profile(user_id, changes)
      when is_map(changes) and map_size(changes) > 0 do
    set = Map.to_list(changes) ++ [updated_at: DateTime.utc_now()]

    Profile
    |> where([p], p.user_id == ^user_id)
    |> Repo.update_all(set: set)

    :ok
  end

  def patch_cached_profile(_user_id, _empty), do: :ok

  # For items stored before profile enrichment worked, fill actor_avatar_url
  # at read-time: first from profiles_cache, then lazy REST for any still missing.
  defp enrich_avatars(items) do
    missing_ids =
      items
      |> Enum.filter(&(&1.actor_id && is_nil(&1.actor_avatar_url)))
      |> Enum.map(& &1.actor_id)
      |> Enum.uniq()

    if missing_ids == [] do
      items
    else
      cached =
        Profile
        |> where([p], p.user_id in ^missing_ids)
        |> select([p], {p.user_id, p.avatar_url})
        |> Repo.all()
        |> Map.new()

      # Fetch profiles not yet in cache via REST (lazy warm-up)
      still_missing = Enum.reject(missing_ids, &Map.has_key?(cached, &1))

      fetched =
        still_missing
        |> Enum.map(fn user_id ->
          case FeedService.Feed.ProfileEnricher.fetch_and_cache(user_id) do
            %{avatar_url: url} when not is_nil(url) -> {user_id, url}
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Map.new()

      avatar_map = Map.merge(cached, fetched)

      Enum.map(items, fn item ->
        if item.actor_id && is_nil(item.actor_avatar_url) do
          %{item | actor_avatar_url: avatar_map[item.actor_id]}
        else
          item
        end
      end)
    end
  end

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

  defp duplicate_event?(%Ecto.Changeset{errors: errors}) do
    match?({_, [{:constraint, :unique} | _]}, errors[:event_id])
  end

end
