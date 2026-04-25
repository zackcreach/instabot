defmodule Instabot.Workers.ScrapeProfileTest do
  use Instabot.DataCase, async: false

  import Ecto.Query
  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Instagram
  alias Instabot.Instagram.ScrapeLog
  alias Instabot.Repo
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

      assert_receive {:scrape_event, %{profile_id: received_id, status: :started}}
      assert inactive_profile.id == received_id
      assert_receive {:scrape_event, %{profile_id: received_id, status: :cancelled}}
      assert inactive_profile.id == received_id
    end

    test "cancels when no instagram connection exists", %{user: user, profile: profile} do
      Phoenix.PubSub.subscribe(Instabot.PubSub, "scrape_updates:#{user.id}")

      assert {:cancel, "no instagram connection"} ==
               ScrapeProfile.perform(%Oban.Job{
                 args: %{"tracked_profile_id" => profile.id}
               })

      assert_receive {:scrape_event, %{profile_id: received_id, status: :started}}
      assert profile.id == received_id
      assert_receive {:scrape_event, %{profile_id: received_id, status: :cancelled}}
      assert profile.id == received_id
    end

    test "cancels when connection is expired", %{user: user, profile: profile} do
      instagram_connection_fixture(user, %{status: "expired"})

      Phoenix.PubSub.subscribe(Instabot.PubSub, "scrape_updates:#{user.id}")

      assert {:cancel, "connection status: expired"} ==
               ScrapeProfile.perform(%Oban.Job{
                 args: %{"tracked_profile_id" => profile.id}
               })

      assert_receive {:scrape_event, %{profile_id: received_id, status: :started}}
      assert profile.id == received_id
      assert_receive {:scrape_event, %{profile_id: received_id, status: :cancelled}}
      assert profile.id == received_id
    end

    test "broadcasts failure when browser startup fails", %{user: user, profile: profile} do
      _connection = connected_connection_fixture(user)
      scraper_config = Application.get_env(:instabot, Instabot.Scraper, [])
      mock_bridge_path = Path.expand("../../../test/support/dist/mock_bridge.js", __DIR__)

      Application.put_env(
        :instabot,
        Instabot.Scraper,
        scraper_config
        |> Keyword.put(:playwright_path, Path.dirname(mock_bridge_path))
        |> Keyword.put(:bridge_script, mock_bridge_path)
      )

      System.put_env("INSTABOT_MOCK_BRIDGE_FAIL_LAUNCH", "true")

      on_exit(fn ->
        Application.put_env(:instabot, Instabot.Scraper, scraper_config)
        System.delete_env("INSTABOT_MOCK_BRIDGE_FAIL_LAUNCH")
      end)

      Phoenix.PubSub.subscribe(Instabot.PubSub, "scrape_updates:#{user.id}")

      assert {:error, _reason} =
               ScrapeProfile.perform(%Oban.Job{
                 args: %{"tracked_profile_id" => profile.id}
               })

      assert_receive {:scrape_event, %{profile_id: received_id, status: :started}}
      assert profile.id == received_id
      assert_receive {:scrape_event, %{profile_id: received_id, status: :scraping_posts}}
      assert profile.id == received_id
      assert_receive {:scrape_event, %{profile_id: received_id, status: :scraping_stories}}
      assert profile.id == received_id
      assert_receive {:scrape_event, %{profile_id: received_id, status: :failed}}
      assert profile.id == received_id

      statuses =
        Repo.all(
          from log in ScrapeLog,
            where: log.tracked_profile_id == ^profile.id,
            select: log.status
        )

      assert ["failed", "failed"] == Enum.sort(statuses)
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
