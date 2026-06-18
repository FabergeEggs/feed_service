defmodule FeedService.Feed do
  import Ecto.Query

  alias FeedService.Repo
  alias FeedService.Feed.{FeedItem, Membership, Profile, Cursor}

  @default_limit 20
  @max_limit 100

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

  defp filter_by_membership(query, nil), do: query
  defp filter_by_membership(query, []), do: where(query, false)

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
    %FeedItem{}
    |> FeedItem.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:source_type, :source_id],
      returning: true
    )
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

  def patch_cached_profile(user_id, changes)
      when is_map(changes) and map_size(changes) > 0 do
    set = Map.to_list(changes) ++ [updated_at: DateTime.utc_now()]

    Profile
    |> where([p], p.user_id == ^user_id)
    |> Repo.update_all(set: set)

    :ok
  end

  def patch_cached_profile(_user_id, _empty), do: :ok

  defp enrich_avatars(items) do
    actor_ids =
      items
      |> Enum.filter(&(&1.actor_id))
      |> Enum.map(& &1.actor_id)
      |> Enum.uniq()

    if actor_ids == [] do
      items
    else
      cached =
        Profile
        |> where([p], p.user_id in ^actor_ids)
        |> select([p], {p.user_id, p.avatar_url})
        |> Repo.all()
        |> Map.new()

      still_missing = Enum.reject(actor_ids, fn id ->
        case Map.get(cached, id) do
          url when is_binary(url) and url != "" -> true
          _ -> false
        end
      end)

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
        if item.actor_id do
          %{item | actor_avatar_url: Map.get(avatar_map, item.actor_id)}
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

end
