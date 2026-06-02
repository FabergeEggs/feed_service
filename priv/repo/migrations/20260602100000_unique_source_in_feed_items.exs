defmodule FeedService.Repo.Migrations.UniqueSourceInFeedItems do
  use Ecto.Migration

  def up do
    # Keep only the most recent row per (source_type, source_id); older duplicates
    # come from repeated "created"/"updated" events that each inserted a new row.
    execute """
    DELETE FROM feed_items
    WHERE id NOT IN (
      SELECT DISTINCT ON (source_type, source_id) id
      FROM feed_items
      ORDER BY source_type, source_id, occurred_at DESC, id DESC
    )
    """

    create unique_index(:feed_items, [:source_type, :source_id],
             name: :feed_items_source_unique
           )
  end

  def down do
    drop index(:feed_items, [:source_type, :source_id], name: :feed_items_source_unique)
  end
end
