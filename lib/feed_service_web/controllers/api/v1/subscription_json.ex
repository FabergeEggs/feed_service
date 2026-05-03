defmodule FeedServiceWeb.Api.V1.SubscriptionJSON do
  alias FeedService.Feed.Subscription

  def index(%{subscriptions: subs}), do: %{items: Enum.map(subs, &data/1)}
  def show(%{subscription: sub}), do: data(sub)

  defp data(%Subscription{} = s) do
    %{
      id: s.id,
      target_type: s.target_type,
      target_id: s.target_id,
      created_at: s.inserted_at
    }
  end
end
