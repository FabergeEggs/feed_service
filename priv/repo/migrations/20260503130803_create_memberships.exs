defmodule FeedService.Repo.Migrations.CreateMemberships do
  use Ecto.Migration

  def change do
    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :binary_id, null: false
      add :project_id, :binary_id, null: false
      add :role, :string, null: false, size: 16
      add :joined_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:memberships, [:user_id, :project_id])
    create index(:memberships, [:project_id])
  end
end
