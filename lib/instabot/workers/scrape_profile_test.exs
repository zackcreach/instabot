defmodule Instabot.Workers.ScrapeProfileTest do
  use Instabot.DataCase, async: true

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Instagram
  alias Instabot.Workers.ScrapeProfile

  setup do
    user = user_fixture()
    profile = tracked_profile_fixture(user)
    %{user: user, profile: profile}
  end

  describe "perform/1" do
    test "cancels when profile is inactive", %{user: user, profile: profile} do
      {:ok, inactive_profile} = Instagram.toggle_active(profile)
      refute inactive_profile.is_active

      Phoenix.PubSub.subscribe(Instabot.PubSub, "scrape_updates:#{user.id}")

      assert {:cancel, "profile is inactive"} ==
               ScrapeProfile.perform(%Oban.Job{
                 args: %{"tracked_profile_id" => inactive_profile.id}
               })

      assert_receive {:scrape_completed, received_id}
      assert inactive_profile.id == received_id
    end

    test "cancels when no instagram connection exists", %{user: user, profile: profile} do
      Phoenix.PubSub.subscribe(Instabot.PubSub, "scrape_updates:#{user.id}")

      assert {:cancel, "no instagram connection"} ==
               ScrapeProfile.perform(%Oban.Job{
                 args: %{"tracked_profile_id" => profile.id}
               })

      assert_receive {:scrape_completed, received_id}
      assert profile.id == received_id
    end

    test "cancels when connection is expired", %{user: user, profile: profile} do
      instagram_connection_fixture(user, %{status: "expired"})

      Phoenix.PubSub.subscribe(Instabot.PubSub, "scrape_updates:#{user.id}")

      assert {:cancel, "connection status: expired"} ==
               ScrapeProfile.perform(%Oban.Job{
                 args: %{"tracked_profile_id" => profile.id}
               })

      assert_receive {:scrape_completed, received_id}
      assert profile.id == received_id
    end

    test "broadcasts scrape_completed on success", %{user: user, profile: profile} do
      _connection = connected_connection_fixture(user)

      Phoenix.PubSub.subscribe(Instabot.PubSub, "scrape_updates:#{user.id}")

      ScrapeProfile.perform(%Oban.Job{
        args: %{"tracked_profile_id" => profile.id}
      })

      assert_receive {:scrape_completed, received_id}
      assert profile.id == received_id
    end
  end

  describe "unique constraint" do
    test "has 5-minute uniqueness window" do
      worker_opts = ScrapeProfile.__opts__()
      unique = worker_opts[:unique]
      assert 300 == unique[:period]
      assert [:tracked_profile_id] == unique[:keys]
    end
  end
end
