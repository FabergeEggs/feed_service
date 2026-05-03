defmodule FeedService.Events.Handlers.ProjectHandler do
  @moduledoc """
  Обрабатывает события из project_service:
    - project.created / project.updated
    - post.create / post.update / post.delete
    - task.create (и create, и update в этом топике) / task.delete
  """

  alias FeedService.Events.Schema
  alias FeedService.Feed
  alias FeedService.Feed.Projector

  @kinds ~w(project_created project_updated
            post_created post_updated post_deleted
            task_created task_updated task_deleted)a

  @doc "Возвращает true, если этот handler знает kind события."
  def handles?(%Schema{kind: kind}), do: kind in @kinds

  @doc "Применяет событие к feed_items. Возвращает :ok | {:error, _}."
  def handle(%Schema{kind: kind} = event) when kind in @kinds do
    case Projector.project(event) do
      {:upsert, attrs} ->
        # TODO(upstream) project_service:
        # На kind == :project_created хорошо бы синхронизировать список
        # участников проекта в локальную таблицу `memberships`. Сейчас в
        # project_service НЕТ событий `member.added` / `member.removed`
        # (см. memory: eggs_event_contracts).
        # ВАРИАНТЫ ИСПРАВЛЕНИЯ:
        #   а) В project_service добавить producer:
        #      - в `services/project_service.py` при `add_member` /
        #        `remove_member` слать в Kafka: `project.member.added`
        #        / `project.member.removed` с {project_id, user_id, role}.
        #      Тогда здесь добавить отдельный handler `MembershipHandler`.
        #   б) feed_service дёргает REST в project_service:
        #      на :project_created → GET /project/{id}/info с расширением
        #      "members" (нужно добавить такой endpoint).
        # До решения — запись попадает только в feed_items, membership-фильтр
        # для лент остаётся пустым.
        with {:ok, _item} <- Feed.upsert_item(attrs) do
          :ok
        end

      {:delete, source_type, source_id} ->
        Feed.delete_by_source(source_type, source_id)
        :ok
    end
  end
end
