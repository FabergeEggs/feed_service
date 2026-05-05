defmodule FeedService.Feed.ProfileEnricherTest do
  use FeedService.DataCase, async: false

  import Hammox

  alias FeedService.Cache
  alias FeedService.Clients.ProfileClientMock
  alias FeedService.Feed
  alias FeedService.Feed.ProfileEnricher

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Cache.invalidate_pattern("profile_fetch_failed:*")
    :ok
  end

  describe "enrich_actor/1" do
    test "returns attrs unchanged when actor_id is nil" do
      attrs = %{actor_id: nil, label: "x"}
      assert ^attrs = ProfileEnricher.enrich_actor(attrs)
    end

    test "uses cached profile when present, no client call" do
      uid = Ecto.UUID.generate()

      {:ok, _} =
        Feed.upsert_profile(%{user_id: uid, name: "alice", avatar_url: "http://a"})

      attrs = %{actor_id: uid, label: "x"}
      enriched = ProfileEnricher.enrich_actor(attrs)

      assert enriched.actor_name == "alice"
      assert enriched.actor_avatar_url == "http://a"
    end

    test "lazy-fetches and writes to profiles_cache when missing" do
      uid = Ecto.UUID.generate()

      expect(ProfileClientMock, :get_profile, fn ^uid ->
        {:ok, %{"name" => "bob", "avatar_url" => "http://b"}}
      end)

      enriched = ProfileEnricher.enrich_actor(%{actor_id: uid})

      assert enriched.actor_name == "bob"
      assert enriched.actor_avatar_url == "http://b"
      assert %{name: "bob", avatar_url: "http://b"} = Feed.lookup_profile(uid)
    end

    test "sets storm flag on fetch error and skips client on subsequent calls" do
      uid = Ecto.UUID.generate()

      expect(ProfileClientMock, :get_profile, fn ^uid -> {:error, :timeout} end)

      attrs = %{actor_id: uid, actor_name: "from event"}

      enriched = ProfileEnricher.enrich_actor(attrs)
      assert enriched.actor_name == "from event"

      enriched2 = ProfileEnricher.enrich_actor(attrs)
      assert enriched2.actor_name == "from event"
    end

    test "does not overwrite event-supplied fields with nil from profile" do
      uid = Ecto.UUID.generate()
      {:ok, _} = Feed.upsert_profile(%{user_id: uid, name: nil, avatar_url: nil})

      attrs = %{actor_id: uid, actor_name: "from event", actor_avatar_url: "http://e"}
      enriched = ProfileEnricher.enrich_actor(attrs)

      assert enriched.actor_name == "from event"
      assert enriched.actor_avatar_url == "http://e"
    end
  end
end
