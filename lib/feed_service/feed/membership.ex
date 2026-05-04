defmodule FeedService.Feed.Membership do
  use Ecto.Schema

  import Ecto.Changeset

  @roles ~w(scientist volunteer)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "memberships" do
    field :user_id, Ecto.UUID
    field :project_id, Ecto.UUID
    field :role, :string
    field :joined_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(user_id project_id role joined_at)a

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, @required)
    |> validate_required(@required)
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:user_id, :project_id],
      name: :memberships_user_id_project_id_index
    )
  end

  def roles, do: @roles
end
