defmodule FeedService.Clients.ProfileClient.Behaviour do
  @callback get_profile(user_id :: String.t()) :: {:ok, map()} | {:error, term()}
end
