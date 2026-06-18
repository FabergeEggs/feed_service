defmodule FeedService.Events.Handlers.ProfileHandler do
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
