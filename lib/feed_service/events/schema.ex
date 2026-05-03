defmodule FeedService.Events.Schema do
  @moduledoc """
  Decodes raw Kafka messages from upstream services into a single,
  uniform internal struct that the projector can work with.

  The decoder routes by **Kafka topic name**, not by the `type` field
  inside payloads — payloads in upstream services are inconsistently
  set today (see memory: `eggs_event_contracts`). The topic name is
  the source of truth.

  All `creator_name`/`creator` field variants are normalized into a
  single `actor_name` here, so the projector and consumers don't need
  to remember which upstream chose which name.
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

  @doc """
  Decodes one Kafka message.

    * `topic` — Kafka topic name (string).
    * `body`  — raw message value (binary, JSON-encoded).

  Returns `{:ok, %Schema{}}` or `{:error, reason}`.
  """
  @spec decode(String.t(), binary()) :: {:ok, t()} | {:error, atom()}
  def decode(topic, body) when is_binary(topic) and is_binary(body) do
    with {:ok, payload} <- Jason.decode(body) do
      decode_topic(topic, payload)
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
    end
  end

  # ── topic routing ────────────────────────────────────────────────────
  #
  # TODO(upstream) project_service:
  # Имена топиков разнобойные. Сейчас project-сервис публикует:
  #   - `project.created` / `project.updated`  (past tense — ОК)
  #   - `post.create` / `post.update` / `post.delete`   (present — нужно)
  #   - `task.create` / `task.delete`                   (present — нужно)
  # ЧТО ИСПРАВИТЬ в `project_service/src/adapters/clients/kafka_producer.py`:
  #   1. Переименовать на past tense:
  #        post.create → post.created
  #        post.update → post.updated
  #        post.delete → post.deleted
  #        task.create → task.created
  #        task.delete → task.deleted
  #   2. Согласовать с response_service: его конфиг ждёт префикс
  #      `project_service.post.created` (см. response_service/src/core/config.py).
  #      Команды должны договориться о префиксе и поправить
  #      ОДНУ ИЗ сторон. Лучше — без префикса, тогда правится только
  #      response_service config.
  # После согласования и фикса обновить строки `decode_topic` ниже.

  defp decode_topic("project.created", p), do: build(:project_created, p, &project_attrs/1)
  defp decode_topic("project.updated", p), do: build(:project_updated, p, &project_attrs/1)

  defp decode_topic("post.create", p), do: build(:post_created, p, &post_attrs/1)
  defp decode_topic("post.update", p), do: build(:post_updated, p, &post_attrs/1)
  defp decode_topic("post.delete", p), do: build(:post_deleted, p, &delete_attrs("post_id", &1))

  # TODO(upstream) project_service:
  # `send_update_task` в `kafka_producer.py:121-138` отправляет update-события
  # в неправильный топик `task.create` (должен быть `task.update`).
  # ЧТО ИСПРАВИТЬ в `project_service/src/adapters/clients/kafka_producer.py:123`:
  #   topic="task.create"  →  topic="task.update"  (а после унификации — "task.updated")
  # Пока баг есть, мы разделяем create/update в этом одном топике
  # по полю `type` внутри payload. После фикса первую clause удалить.
  defp decode_topic("task.create", %{"type" => "task.update"} = p),
    do: build(:task_updated, p, &task_attrs/1)

  defp decode_topic("task.create", p), do: build(:task_created, p, &task_attrs/1)
  defp decode_topic("task.delete", p), do: build(:task_deleted, p, &delete_attrs("task_id", &1))

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

  # ── attribute normalizers ────────────────────────────────────────────

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

  defp post_attrs(%{"post_id" => pid, "project_id" => proj, "creator_id" => creator_id} = p) do
    {:ok,
     %{
       source_id: pid,
       project_id: proj,
       actor_id: creator_id,
       # TODO(upstream) project_service:
       # post/task-события несут поле `creator` (имя строкой), а
       # project-события — `creator_name`. Унифицировать.
       # ЧТО ИСПРАВИТЬ в `project_service/src/adapters/clients/kafka_producer.py`:
       # в send_create_post / send_update_post / send_create_task / send_update_task
       # переименовать ключ payload `"creator": post.creator` → `"creator_name": post.creator`.
       # После этого fallback `|| p["creator_name"]` ниже можно убрать.
       actor_name: p["creator"] || p["creator_name"],
       label: p["label"],
       short_description: p["short_description"],
       description: p["description"],
       occurred_at: pick_time(p)
     }}
  end

  defp post_attrs(_), do: {:error, :missing_fields}

  defp task_attrs(%{"task_id" => tid, "project_id" => proj, "creator_id" => creator_id} = p) do
    {:ok,
     %{
       source_id: tid,
       project_id: proj,
       actor_id: creator_id,
       # TODO(upstream) project_service: см. комментарий в post_attrs выше —
       # тот же fallback `creator` || `creator_name` нужен по той же причине.
       # Также: payload task несёт `answer_count` строкой (`"15"`), а должен
       # числом. См. `project_service/src/adapters/clients/kafka_producer.py:115`:
       #   "answer_count": str(task.answers_count)  →  "answer_count": task.answers_count
       # Сейчас feed_service это поле не использует, но клиенты других
       # сервисов точно споткнутся.
       actor_name: p["creator"] || p["creator_name"],
       label: p["label"],
       short_description: p["short_description"],
       description: p["description"],
       occurred_at: pick_time(p)
     }}
  end

  defp task_attrs(_), do: {:error, :missing_fields}

  defp response_attrs(%{"response_id" => rid, "task_id" => tid} = p) do
    {:ok,
     %{
       source_id: rid,
       # TODO(upstream) response_service:
       # Payload `response_service.response.add` НЕ содержит `project_id`.
       # Без него feed_item не попадёт в фильтр project-feed (project_id=nil).
       # ЧТО ДОБАВИТЬ в response_service:
       #   при создании response уже известен task → project_id (response_service
       #   делает запрос в project_service за task → должен включать project_id).
       #   В payload Kafka добавить ключ "project_id".
       # См. response_service/src/services/response_service.py — метод
       # `add_response`, вызов `_kafka.send_response_add(...)`.
       # До исправления — здесь либо REST-обогащение в ResponseHandler,
       # либо запись с project_id=nil (отображается только в user-timeline).
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
      id when is_binary(id) ->
        {:ok, %{source_id: id, occurred_at: pick_time(p)}}

      _ ->
        {:error, :missing_fields}
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────

  # Producers stamp events with one of `created_at`, `updated_at`,
  # `timestamp` (or several at once). We pick the most specific
  # available one and fall back to "now" if nothing parsed.
  defp pick_time(p) do
    iso = p["created_at"] || p["updated_at"] || p["timestamp"]

    case iso && DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end
end
