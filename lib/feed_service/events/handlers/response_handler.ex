defmodule FeedService.Events.Handlers.ResponseHandler do
  alias FeedService.Events.Schema
  alias FeedService.Feed
  alias FeedService.Feed.{ProfileEnricher, Projector}

  @kinds ~w(response_added response_deleted)a

  def handles?(%Schema{kind: kind}), do: kind in @kinds

  def handle(%Schema{kind: kind} = event) when kind in @kinds do
    case Projector.project(event) do
      {:upsert, attrs} ->
        attrs = ProfileEnricher.enrich_actor(attrs)
        with {:ok, _} <- Feed.upsert_item(attrs), do: :ok

      {:delete, source_type, source_id} ->
        Feed.delete_by_source(source_type, source_id)
        :ok
    end
  end
end
