defmodule FeedService.Clients.ProfileClient do
  @moduledoc """
  HTTP-клиент для profile_service. Используется для **lazy** наполнения
  локальной таблицы `profiles_cache` при cold-miss-е (когда обогащаем
  feed-item-ы actor_name/actor_avatar_url).

  TODO(upstream) profile_service — отсутствие producer-а Kafka:
  Сейчас profile_service не публикует события `profile.changed`,
  поэтому единственный способ обновить наш кеш — синхронный REST.
  Когда producer появится (см. ProfileHandler), `ProfileClient` станет
  fallback-ом, а основным источником станет Kafka.
  Подробности — в `ProfileHandler` и memory: eggs_event_contracts.

  TODO(upstream) profile_service — base_url:
  В FastAPI handlers.py объявлены прямые маршруты `@app.get("/{id}")`,
  без префикса. Если у profile_service в проде монтируется prefix
  `/profile` (через `app.include_router(router, prefix="/profile")`),
  то путь будет `GET /profile/{id}`. Нужно уточнить у команды
  profile_service фактический live-путь и при необходимости
  поправить `@profile_path` ниже.

  TODO(upstream) profile_service — auth:
  Тот же вопрос S2S-токенов, что и для project_service. Сейчас
  отправляем `X-User-Id`/`X-Username` с sentinel-значениями.
  """

  require Logger

  # Путь к ресурсу профиля. Уточнить с командой profile_service —
  # см. TODO выше.
  @profile_path "/{id}"

  @doc """
  Получает профиль по user_id.

    * `{:ok, map}`           — JSON-тело `ProfileDTO` (id, name, email, ...)
    * `{:error, :not_found}` — 404, профиля нет
    * `{:error, :not_configured}` — base_url не задан
    * `{:error, term}`       — сеть/HTTP
  """
  def get_profile(user_id) when is_binary(user_id) do
    request(:get, String.replace(@profile_path, "{id}", user_id))
  end

  defp request(method, path) do
    config = Application.fetch_env!(:feed_service, :profile_client)

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
      headers: [
        {"x-user-id", "00000000-0000-0000-0000-000000000000"},
        {"x-username", "feed-service"}
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
