defmodule FeedService.Events.Handlers.ResponseHandler do
  alias FeedService.Events.Schema
  alias FeedService.Feed
  alias FeedService.Feed.Projector

  @kinds ~w(response_added response_deleted)a

  def handles?(%Schema{kind: kind}), do: kind in @kinds

  # TODO(upstream) response_service: payload lacks project_id — items end up
  # with project_id=nil and won't appear in project-scoped feeds. Either
  # response_service publishes project_id, or we add REST enrichment here.
  def handle(%Schema{kind: kind} = event) when kind in @kinds do
    case Projector.project(event) do
      {:upsert, attrs} ->
        with {:ok, _} <- Feed.upsert_item(attrs), do: :ok

      {:delete, source_type, source_id} ->
        Feed.delete_by_source(source_type, source_id)
        :ok
    end
  end
end
