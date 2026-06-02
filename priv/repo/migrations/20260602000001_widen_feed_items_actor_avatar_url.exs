defmodule FeedService.Repo.Migrations.WidenFeedItemsActorAvatarUrl do
  use Ecto.Migration

  def change do
    alter table(:feed_items) do
      modify :actor_avatar_url, :text
    end
  end
end
