defmodule FeedService.Events.Handlers.ProjectHandler do
  alias FeedService.Events.Schema
  alias FeedService.Feed
  alias FeedService.Feed.Projector

  @kinds ~w(project_created project_updated
            post_created post_updated post_deleted
            task_created task_updated task_deleted)a

  def handles?(%Schema{kind: kind}), do: kind in @kinds

  # TODO(upstream) project_service: publish member.added/member.removed events
  # so we can populate `memberships` from Kafka. Until then it stays empty
  # or we'd need a REST pull on project.created.
  def handle(%Schema{kind: kind} = event) when kind in @kinds do
    case Projector.project(event) do
      {:upsert, attrs} ->
        with {:ok, _item} <- Feed.upsert_item(attrs), do: :ok

      {:delete, source_type, source_id} ->
        Feed.delete_by_source(source_type, source_id)
        :ok
    end
  end
end
