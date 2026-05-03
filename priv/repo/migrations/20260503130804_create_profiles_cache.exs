defmodule FeedService.Repo.Migrations.CreateProfilesCache do
  use Ecto.Migration

  def change do
    create table(:profiles_cache, primary_key: false) do
      add :user_id, :binary_id, primary_key: true
      add :name, :string
      add :avatar_url, :string

      timestamps(type: :utc_datetime_usec)
    end
  end
end
