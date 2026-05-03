defmodule FeedService.Events.Handlers.ResponseHandler do
  @moduledoc """
  Обрабатывает события из response_service:
    - response_service.response.add    (kind: :response_added)
    - response_service.response.delete (kind: :response_deleted)
  """

  alias FeedService.Events.Schema
  alias FeedService.Feed
  alias FeedService.Feed.Projector

  @kinds ~w(response_added response_deleted)a

  def handles?(%Schema{kind: kind}), do: kind in @kinds

  def handle(%Schema{kind: kind} = event) when kind in @kinds do
    case Projector.project(event) do
      {:upsert, attrs} ->
        # TODO(upstream) response_service:
        # Payload `response_service.response.add` не содержит `project_id`.
        # Без него запись не попадёт в фильтр project-feed
        # (`Feed.list_project_feed/2` ищет по `project_id`).
        #
        # ЧТО ДОБАВИТЬ в response_service/src/services/response_service.py
        # (метод `add_response`, вызов `_kafka.send_response_add(...)`):
        #   await self._kafka.send_response_add(
        #     str(created.id), str(created.task_id),
        #     str(created.user_id), str(created.project_id)   # ← новое поле
        #   )
        # И в payload вставить "project_id". В response должен быть
        # доступен project_id (либо приходит при создании, либо
        # response_service делает lookup в project_service).
        #
        # ВРЕМЕННОЕ РЕШЕНИЕ: пока поле не добавили, можно сделать
        # синхронный REST-вызов из этого handler-а:
        #   ProjectClient.get_task_project(attrs.payload["task_id"])
        # и обогатить attrs. Я этот вызов пока не реализую — REST-клиент
        # ProjectClient появится в этапе 7. До тех пор проект-фильтр
        # для response-событий не работает.
        with {:ok, _} <- Feed.upsert_item(attrs) do
          :ok
        end

      {:delete, source_type, source_id} ->
        Feed.delete_by_source(source_type, source_id)
        :ok
    end
  end
end
