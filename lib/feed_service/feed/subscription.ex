defmodule FeedService.Feed.Subscription do
  @moduledoc """
  A user's subscription to a feed source — a project, another user, or
  a tag. Combined with `Membership` it builds the WHERE-clause that
  filters `feed_items` for the user's personal timeline.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @target_types ~w(project user tag)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "subscriptions" do
    field :user_id, Ecto.UUID
    field :target_type, :string
    field :target_id, Ecto.UUID

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required ~w(user_id target_type target_id)a

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, @required)
    |> validate_required(@required)
    |> validate_inclusion(:target_type, @target_types)
    |> unique_constraint([:user_id, :target_type, :target_id],
      name: :subscriptions_user_id_target_type_target_id_index
    )
  end

  def target_types, do: @target_types
end
