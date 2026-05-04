defmodule FeedService.Events.Handlers.ProfileHandler do
  @moduledoc """
  Stub for `profile_service.profile.changed`. The producer doesn't exist
  in profile_service yet (no Kafka producer in that service at all).
  Broadway is not subscribed to a profile topic until the producer ships.
  """

  alias FeedService.Events.Schema

  @kinds [:profile_changed]

  def handles?(%Schema{kind: kind}), do: kind in @kinds

  # TODO(upstream) profile_service: add Kafka producer publishing
  # `profile_service.profile.changed` with {user_id, name, avatar_url}.
  # When ready, replace body with `Feed.upsert_profile/1` and add the
  # topic to events/broadway.ex `@topics`.
  def handle(%Schema{kind: :profile_changed}), do: :ok
end
