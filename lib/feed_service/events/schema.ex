defmodule FeedService.Events.Schema do
  @moduledoc """
  Decodes raw Kafka messages into a uniform internal struct. Routing is by
  topic name, not by payload `type` (latter is buggy upstream).
  """

  defstruct [:kind, :attrs, :raw]

  @type kind ::
          :project_created
          | :project_updated
          | :post_created
          | :post_updated
          | :post_deleted
          | :task_created
          | :task_updated
          | :task_deleted
          | :response_added
          | :response_deleted

  @type t :: %__MODULE__{kind: kind(), attrs: map(), raw: map()}

  @spec decode(String.t(), binary()) :: {:ok, t()} | {:error, atom()}
  def decode(topic, body) when is_binary(topic) and is_binary(body) do
    with {:ok, payload} <- Jason.decode(body) do
      decode_topic(topic, payload)
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
    end
  end

  defp decode_topic("project.created", p), do: build(:project_created, p, &project_attrs/1)
  defp decode_topic("project.updated", p), do: build(:project_updated, p, &project_attrs/1)

  defp decode_topic("post.created", p), do: build(:post_created, p, &post_attrs/1)
  defp decode_topic("post.updated", p), do: build(:post_updated, p, &post_attrs/1)
  defp decode_topic("post.deleted", p), do: build(:post_deleted, p, &delete_attrs("post_id", &1))

  defp decode_topic("task.created", p), do: build(:task_created, p, &task_attrs/1)
  defp decode_topic("task.updated", p), do: build(:task_updated, p, &task_attrs/1)
  defp decode_topic("task.deleted", p), do: build(:task_deleted, p, &delete_attrs("task_id", &1))

  defp decode_topic("response_service.response.add", p),
    do: build(:response_added, p, &response_attrs/1)

  defp decode_topic("response_service.response.delete", p),
    do: build(:response_deleted, p, &response_attrs/1)

  defp decode_topic(_, _), do: {:error, :unknown_topic}

  defp build(kind, raw, normalize) do
    case normalize.(raw) do
      {:ok, attrs} -> {:ok, %__MODULE__{kind: kind, attrs: attrs, raw: raw}}
      {:error, _} = err -> err
    end
  end

  defp project_attrs(%{"project_id" => pid, "label" => label, "creator_id" => creator_id} = p) do
    {:ok,
     %{
       source_id: pid,
       project_id: pid,
       actor_id: creator_id,
       actor_name: p["creator_name"] || p["creator"],
       label: label,
       short_description: p["short_description"],
       description: p["description"],
       occurred_at: pick_time(p)
     }}
  end

  defp project_attrs(_), do: {:error, :missing_fields}

  # TODO(upstream) project_service: rename payload field `creator` → `creator_name`
  # in send_create_post/send_update_post/send_create_task/send_update_task.
  defp post_attrs(%{"post_id" => pid, "project_id" => proj, "creator_id" => creator_id} = p) do
    {:ok,
     %{
       source_id: pid,
       project_id: proj,
       actor_id: creator_id,
       actor_name: p["creator"] || p["creator_name"],
       label: p["label"],
       short_description: p["short_description"],
       description: p["description"],
       occurred_at: pick_time(p)
     }}
  end

  defp post_attrs(_), do: {:error, :missing_fields}

  # TODO(upstream) project_service: payload `answer_count` is a string
  # (kafka_producer.py:115), should be int.
  defp task_attrs(%{"task_id" => tid, "project_id" => proj, "creator_id" => creator_id} = p) do
    {:ok,
     %{
       source_id: tid,
       project_id: proj,
       actor_id: creator_id,
       actor_name: p["creator"] || p["creator_name"],
       label: p["label"],
       short_description: p["short_description"],
       description: p["description"],
       occurred_at: pick_time(p)
     }}
  end

  defp task_attrs(_), do: {:error, :missing_fields}

  # TODO(upstream) response_service: include `project_id` in payload of
  # response.add/delete. Without it response items can't be filtered into
  # project-scoped feeds.
  defp response_attrs(%{"response_id" => rid, "task_id" => tid} = p) do
    {:ok,
     %{
       source_id: rid,
       project_id: nil,
       actor_id: p["user_id"],
       actor_name: nil,
       label: nil,
       payload: %{"task_id" => tid},
       occurred_at: pick_time(p)
     }}
  end

  defp response_attrs(_), do: {:error, :missing_fields}

  defp delete_attrs(id_key, %{} = p) do
    case p[id_key] do
      id when is_binary(id) -> {:ok, %{source_id: id, occurred_at: pick_time(p)}}
      _ -> {:error, :missing_fields}
    end
  end

  defp pick_time(p) do
    iso = p["created_at"] || p["updated_at"] || p["timestamp"]

    case iso && DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end
end
