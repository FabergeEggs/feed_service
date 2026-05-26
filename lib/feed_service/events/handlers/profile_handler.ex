defmodule FeedService.Events.Handlers.ProfileHandler do
  @moduledoc """
  Keeps `profiles_cache` fresh from profile_service Kafka events.

  profile_service publishes two event types to the `user-events` topic:
    - user.profile.updated  → {user_id, name}
    - user.avatar.updated   → {user_id, avatar_link}

  Each event carries only one changed field. We do a partial UPDATE so a
  name-only event never wipes out a cached avatar_url, and vice versa.
  If the user isn't in the cache yet, the UPDATE is a no-op — ProfileEnricher
  will insert a fresh full row on the next REST fetch.
  """

  alias FeedService.Events.Schema
  alias FeedService.Feed

  @kinds [:profile_changed]

  def handles?(%Schema{kind: kind}), do: kind in @kinds

  def handle(%Schema{kind: :profile_changed, attrs: attrs}) do
    changes =
      attrs
      |> Map.take([:name, :avatar_url])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Feed.patch_cached_profile(attrs.user_id, changes)
    :ok
  end
end
