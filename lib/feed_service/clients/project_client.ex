defmodule FeedService.Clients.ProjectClient do
  @moduledoc """
  HTTP-клиент для project_service. Используется для:
    * подтверждения существования проекта;
    * (в будущем) подтягивания списка участников при `project.created`,
      пока в project_service нет события `member.added`.

  Авторизация: project_service ждёт заголовки `X-User-Id`/`X-Username`/
  `X-User-Roles`. Для S2S-вызовов передаём фиксированный sentinel
  `feed-service` в заголовках — это договорённость, до тех пор пока
  команда не добавит реальный S2S-механизм.

  TODO(upstream) project_service — service-to-service auth:
  Сейчас project_service не различает «человек» и «другой сервис».
  Любой запрос с заголовками `X-User-Id`/`X-Username` принимается как
  пользователь. Это потенциальная дыра: если злоумышленник попадёт
  в внутреннюю сеть, он подделает заголовки.
  ЧТО ИСПРАВИТЬ:
    1. Добавить в project_service плагины проверки `X-Service-Token`
       (см. media_service — там уже есть готовый паттерн в
       `MediaServiceWeb.Plugs.S2SAuth`).
    2. Завести env-переменную `PROJECT_SERVICE_TOKENS` с CSV
       `feed-service:<token>,response-service:<token>,...`.
    3. feed_service будет слать `X-Service-Token` вместо подделки
       user-headers.
  """

  require Logger

  @doc """
  Получает детали проекта.

    * `{:ok, map}`           — JSON ответа `GET /project/{id}/info`
    * `{:error, :not_found}` — 404
    * `{:error, :not_configured}` — base_url не задан
    * `{:error, term}`       — сетевая/прочая ошибка
  """
  def get_project(project_id) when is_binary(project_id) do
    request(:get, "/project/#{project_id}/info")
  end

  # TODO(upstream) project_service:
  # Чтобы обогатить feed_item для response_added (получить project_id
  # по task_id), feed_service должен иметь endpoint вида
  # `GET /task/{task_id}` без знания project_id заранее.
  # Сейчас в project_service есть только `GET /project/{pid}/task/{tid}` —
  # требует знать pid. Это chicken-and-egg.
  # ВАРИАНТЫ ИСПРАВЛЕНИЯ:
  #   а) Добавить endpoint `GET /task/{task_id}` в project_service
  #      (`src/api/http/project_router.py`), который возвращает task
  #      вместе с project_id.
  #   б) response_service публикует project_id в payload Kafka
  #      (см. TODO в response_handler.ex). Это правильнее, так как
  #      response_service уже знает project_id при создании ответа.
  # До исправления функция `get_task_project_id/1` ниже не реализована.
  # @doc "Возвращает project_id для task_id. НЕ РЕАЛИЗОВАНО."
  # def get_task_project_id(task_id), do: {:error, :not_implemented}

  defp request(method, path) do
    config = Application.fetch_env!(:feed_service, :project_client)

    case config[:base_url] do
      url when is_binary(url) and url != "" ->
        do_request(method, build_url(url, path))

      _ ->
        {:error, :not_configured}
    end
  end

  defp do_request(method, url) do
    Req.request(
      method: method,
      url: url,
      # TODO(upstream): заменить на `X-Service-Token: ...` после
      # добавления S2S-плагина в project_service.
      headers: [
        {"x-user-id", "00000000-0000-0000-0000-000000000000"},
        {"x-username", "feed-service"},
        {"x-user-roles", "service"}
      ],
      receive_timeout: 5_000,
      retry: false
    )
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: 404}} -> {:error, :not_found}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_url(base, path), do: String.trim_trailing(base, "/") <> path
end
