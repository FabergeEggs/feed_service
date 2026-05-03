defmodule FeedService.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :binary_id, null: false
      add :target_type, :string, null: false, size: 16
      add :target_id, :binary_id, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:subscriptions, [:user_id, :target_type, :target_id])
    create index(:subscriptions, [:target_type, :target_id])
  end
end
