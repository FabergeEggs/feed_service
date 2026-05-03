defmodule FeedService.Feed.FeedItem do
  @moduledoc """
  A projection of a single upstream event into the unified timeline.

  Created from RedPanda messages by `FeedService.Feed.Projector` and
  written to Postgres by event handlers. `event_id` enforces idempotency:
  the same Kafka delivery cannot produce two rows.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @source_types ~w(project post task response)
  @verbs ~w(created updated deleted answered)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "feed_items" do
    field :source_type, :string
    field :source_id, Ecto.UUID
    field :project_id, Ecto.UUID
    field :actor_id, Ecto.UUID
    field :actor_name, :string
    field :actor_avatar_url, :string
    field :verb, :string
    field :label, :string
    field :short_description, :string
    field :description, :string
    field :media_ids, {:array, Ecto.UUID}, default: []
    field :payload, :map, default: %{}
    field :event_id, :string
    field :occurred_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(source_type source_id verb event_id occurred_at)a
  @optional ~w(project_id actor_id actor_name actor_avatar_url label
               short_description description media_ids payload)a

  @doc """
  Builds a changeset for inserting/updating a feed item.

  Use with `on_conflict: {:replace, ...}, conflict_target: :event_id`
  for idempotent upserts driven by Kafka redeliveries.
  """
  def changeset(item, attrs) do
    item
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:verb, @verbs)
    |> validate_length(:short_description, max: 500)
    |> validate_length(:label, max: 255)
    |> unique_constraint(:event_id)
  end

  @doc "Allowed source_type values."
  def source_types, do: @source_types

  @doc "Allowed verb values."
  def verbs, do: @verbs
end
