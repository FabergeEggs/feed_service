defmodule FeedService.Feed.Projector do
  @moduledoc "Pure transform: `Schema` event → `{:upsert, attrs} | {:delete, source_type, source_id}`."

  alias FeedService.Events.Schema

  @spec project(Schema.t()) ::
          {:upsert, map()} | {:delete, String.t(), String.t()}
  def project(%Schema{kind: kind, attrs: attrs, raw: raw}) do
    case classify(kind) do
      {:upsert, source_type, verb} ->
        {:upsert, build_upsert(source_type, verb, attrs, raw)}

      {:delete, source_type} ->
        {:delete, source_type, attrs.source_id}
    end
  end

  defp classify(:project_created), do: {:upsert, "project", "created"}
  defp classify(:project_updated), do: {:upsert, "project", "updated"}
  defp classify(:post_created), do: {:upsert, "post", "created"}
  defp classify(:post_updated), do: {:upsert, "post", "updated"}
  defp classify(:post_deleted), do: {:delete, "post"}
  defp classify(:task_created), do: {:upsert, "task", "created"}
  defp classify(:task_updated), do: {:upsert, "task", "updated"}
  defp classify(:task_deleted), do: {:delete, "task"}
  defp classify(:response_added), do: {:upsert, "response", "answered"}
  defp classify(:response_deleted), do: {:delete, "response"}

  defp build_upsert(source_type, verb, attrs, raw) do
    %{
      source_type: source_type,
      source_id: attrs.source_id,
      project_id: attrs[:project_id],
      actor_id: attrs[:actor_id],
      actor_name: attrs[:actor_name],
      verb: verb,
      label: attrs[:label],
      short_description: attrs[:short_description],
      description: attrs[:description],
      payload: attrs[:payload] || raw,
      occurred_at: attrs.occurred_at,
      event_id: build_event_id(source_type, verb, attrs)
    }
  end

  defp build_event_id(source_type, verb, %{source_id: id, occurred_at: at}) do
    "#{source_type}:#{id}:#{verb}:#{DateTime.to_iso8601(at)}"
  end
end
