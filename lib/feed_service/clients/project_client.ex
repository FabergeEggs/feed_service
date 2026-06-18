defmodule FeedService.Clients.ProjectClient do
  # TODO(s2s-auth)

  require Logger

  def get_project(project_id) when is_binary(project_id) do
    request(:get, "/project/#{project_id}/info")
  end

  def get_user_memberships(user_id) when is_binary(user_id) do
    request(:get, "/project/profile/#{user_id}")
  end

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
