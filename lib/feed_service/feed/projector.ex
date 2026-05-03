defmodule FeedService.Feed.Projector do
  @moduledoc """
  Pure transformation: `Schema` event → action for the `Feed` context.

  No DB I/O happens here — the projector returns one of:

    * `{:upsert, attrs}`    — pass `attrs` to `Feed.upsert_item/1`
    * `{:delete, source_type, source_id}` — pass to `Feed.delete_by_source/2`

  This separation keeps the projector trivially testable and lets
  handlers decide how to combine multiple actions in a transaction.
  """

  alias FeedService.Events.Schema

  @doc "Projects one event into a feed action."
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

  # ── classify event kind into action + source_type/verb ─────────────

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

  # Deterministic event_id for idempotency. Same inputs → same id, so
  # Kafka redeliveries hit the unique index in `feed_items.event_id` and
  # we get `{:ok, :duplicate}` from `Feed.upsert_item/1`.
  defp build_event_id(source_type, verb, %{source_id: id, occurred_at: at}) do
    "#{source_type}:#{id}:#{verb}:#{DateTime.to_iso8601(at)}"
  end
end
