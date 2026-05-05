ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(FeedService.Repo, :manual)

Hammox.defmock(FeedService.Clients.ProfileClientMock,
  for: FeedService.Clients.ProfileClient.Behaviour
)
