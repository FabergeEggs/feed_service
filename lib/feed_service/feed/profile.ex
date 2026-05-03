defmodule FeedService.Feed.Profile do
  @moduledoc """
  Denormalized cache of upstream profile data.

  Used to enrich `actor_name` / `actor_avatar_url` on incoming events
  without an HTTP round-trip to profile_service. Updated by
  `ProfileHandler` on `profile_service.profile.changed` events; missing
  rows are tolerated (`actor_*` fields then come straight from the
  source event payload).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:user_id, Ecto.UUID, autogenerate: false}
  @foreign_key_type :binary_id
  @derive {Phoenix.Param, key: :user_id}

  schema "profiles_cache" do
    field :name, :string
    field :avatar_url, :string

    timestamps(type: :utc_datetime_usec)
  end

  @cast_fields ~w(user_id name avatar_url)a

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @cast_fields)
    |> validate_required([:user_id])
  end
end
