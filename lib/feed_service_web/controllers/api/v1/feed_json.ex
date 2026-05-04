defmodule FeedServiceWeb.Api.V1.FeedJSON do
  alias FeedService.Feed.FeedItem

  def page(%{page: %{items: items, next_cursor: next_cursor}}) do
    %{
      items: Enum.map(items, &item/1),
      next_cursor: next_cursor,
      has_more: not is_nil(next_cursor)
    }
  end

  defp item(%FeedItem{} = i) do
    %{
      id: i.id,
      source_type: i.source_type,
      source_id: i.source_id,
      project_id: i.project_id,
      actor_id: i.actor_id,
      actor_name: i.actor_name,
      actor_avatar_url: i.actor_avatar_url,
      verb: i.verb,
      label: i.label,
      short_description: i.short_description,
      description: i.description,
      media_ids: i.media_ids,
      occurred_at: i.occurred_at,
      payload: i.payload
    }
  end
end
