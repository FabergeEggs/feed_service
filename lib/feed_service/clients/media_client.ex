defmodule FeedService.Clients.MediaClient do
  @moduledoc """
  HTTP-клиент для media_service. Используется для обогащения ленты
  метаданными вложений (`feed_items.media_ids`).

  Авторизация — S2S через заголовок `X-Service-Token`. Токен и
  base_url берутся из `Application.get_env(:feed_service, :media_client)`
  (см. `config/config.exs` + `runtime.exs`).
  """

  require Logger

  @doc """
  Получает один asset по id.

  Возвращает:
    * `{:ok, map()}`        — JSON-тело ответа
    * `{:error, :not_found}` — 404
    * `{:error, :not_configured}` — base_url не задан
    * `{:error, term()}`    — сеть/HTTP/что-то ещё
  """
  def get_asset(asset_id) when is_binary(asset_id) do
    request(:get, "/api/v1/assets/#{asset_id}")
  end

  @doc """
  Параллельно запрашивает несколько asset-ов. Возвращает map id → результат.

  Каждый id получает свой `{:ok, map}` либо `{:error, _}` независимо —
  одна ошибка не валит весь батч.
  """
  def batch_get_assets(ids) when is_list(ids) do
    ids
    |> Task.async_stream(&{&1, get_asset(&1)},
      max_concurrency: 8,
      timeout: 5_000,
      on_timeout: :kill_task
    )
    |> Enum.into(%{}, fn
      {:ok, {id, result}} -> {id, result}
      {:exit, reason} -> {nil, {:error, {:task_exit, reason}}}
    end)
    |> Map.delete(nil)
  end

  defp request(method, path) do
    config = Application.fetch_env!(:feed_service, :media_client)

    case config[:base_url] do
      url when is_binary(url) and url != "" ->
        do_request(method, build_url(url, path), config[:token])

      _ ->
        {:error, :not_configured}
    end
  end

  defp do_request(method, url, token) do
    Req.request(
      method: method,
      url: url,
      headers: [{"x-service-token", token || ""}],
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
