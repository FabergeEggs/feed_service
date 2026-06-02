defmodule FeedService.Repo.Migrations.WidenProfilesCacheAvatarUrl do
  use Ecto.Migration

  def change do
    alter table(:profiles_cache) do
      modify :avatar_url, :text
    end
  end
end
