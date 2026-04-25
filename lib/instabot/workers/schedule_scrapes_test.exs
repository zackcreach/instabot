defmodule Instabot.Workers.ScheduleScrapesTest do
  use Instabot.DataCase, async: true
  use Oban.Testing, repo: Instabot.Repo

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Instagram
  alias Instabot.Workers.ScheduleScrapes
  alias Instabot.Workers.ScrapeProfile

  describe "perform/1" do
    test "enqueues scrape jobs for active profiles" do
      user = user_fixture()
      active_profile = tracked_profile_fixture(user, %{instagram_username: "active_user"})
      inactive_profile = tracked_profile_fixture(user, %{instagram_username: "inactive_user"})
      {:ok, _} = Instagram.toggle_active(inactive_profile)

      assert :ok == ScheduleScrapes.perform(%Oban.Job{})

      assert_enqueued(worker: ScrapeProfile, args: %{tracked_profile_id: active_profile.id})
      refute_enqueued(worker: ScrapeProfile, args: %{tracked_profile_id: inactive_profile.id})
    end

    test "succeeds with no active profiles" do
      assert :ok == ScheduleScrapes.perform(%Oban.Job{})
    end
  end
end
