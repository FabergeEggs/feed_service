defmodule FeedService.Repo.Migrations.CreateFeedItems do
  use Ecto.Migration

  def change do
    create table(:feed_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_type, :string, null: false, size: 16
      add :source_id, :binary_id, null: false
      add :project_id, :binary_id
      add :actor_id, :binary_id
      add :actor_name, :string
      add :actor_avatar_url, :string
      add :verb, :string, null: false, size: 16
      add :label, :string
      add :short_description, :string, size: 500
      add :description, :text
      add :media_ids, {:array, :binary_id}, null: false, default: []
      add :payload, :map, null: false, default: %{}
      add :event_id, :string, null: false
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:feed_items, [:event_id])
    create index(:feed_items, [:source_type, :source_id])

    # Composite keyset-pagination indexes. `id` is the tie-breaker for
    # rows sharing `occurred_at` to the microsecond.
    create index(:feed_items, ["occurred_at DESC", "id DESC"], name: :feed_items_occurred_at_id_idx)

    create index(
             :feed_items,
             [:project_id, "occurred_at DESC", "id DESC"],
             name: :feed_items_project_occurred_at_id_idx,
             where: "project_id IS NOT NULL"
           )

    create index(
             :feed_items,
             [:actor_id, "occurred_at DESC", "id DESC"],
             name: :feed_items_actor_occurred_at_id_idx,
             where: "actor_id IS NOT NULL"
           )
  end
end
