defmodule FeedService.Feed.ProfileEnricher do
  @moduledoc """
  Fills `actor_name` / `actor_avatar_url` on event attrs from
  `profiles_cache`, lazily fetching missing profiles via REST.

  Storm guard: a failed fetch sets a 5-minute Redis flag so a flapping
  profile_service doesn't get hammered on every Kafka event.
  """

  alias FeedService.Cache
  alias FeedService.Feed
  alias FeedService.Feed.Profile

  @fail_ttl 300

  @doc "Returns the same attrs map, possibly with actor_name / actor_avatar_url filled in."
  def enrich_actor(attrs) do
    case attrs[:actor_id] do
      id when is_binary(id) -> apply_profile(attrs, lookup_or_fetch(id))
      _ -> attrs
    end
  end

  defp apply_profile(attrs, nil), do: attrs

  defp apply_profile(attrs, %{name: name, avatar_url: avatar_url}) do
    attrs
    |> maybe_put(:actor_name, name)
    |> maybe_put(:actor_avatar_url, avatar_url)
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  defp lookup_or_fetch(user_id) do
    case Feed.lookup_profile(user_id) do
      %Profile{name: name, avatar_url: avatar_url} ->
        %{name: name, avatar_url: avatar_url}

      nil ->
        maybe_fetch(user_id)
    end
  end

  defp maybe_fetch(user_id) do
    case Cache.get(failed_key(user_id)) do
      {:ok, _} ->
        nil

      _ ->
        do_fetch(user_id)
    end
  end

  defp do_fetch(user_id) do
    case profile_client().get_profile(user_id) do
      {:ok, body} ->
        attrs = %{
          user_id: user_id,
          name: body["name"],
          avatar_url: body["avatar_url"]
        }

        case Feed.upsert_profile(attrs) do
          {:ok, _} -> %{name: attrs.name, avatar_url: attrs.avatar_url}
          _ -> nil
        end

      {:error, _reason} ->
        Cache.put(failed_key(user_id), true, @fail_ttl)
        nil
    end
  end

  defp profile_client do
    Application.get_env(:feed_service, :profile_client_impl, FeedService.Clients.ProfileClient)
  end

  defp failed_key(user_id), do: "profile_fetch_failed:#{user_id}"
end
