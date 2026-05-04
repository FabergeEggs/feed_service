defmodule FeedService.Clients.ProfileClient do
  @moduledoc """
  REST client for profile_service. Used for lazy `profiles_cache` fills.

  TODO(upstream) profile_service: add Kafka producer for `profile.changed`;
  this REST path is the fallback. Also confirm route prefix (`/{id}` vs
  `/profile/{id}`). Same S2S sentinel-headers caveat as ProjectClient.
  """

  require Logger

  @profile_path "/{id}"

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
