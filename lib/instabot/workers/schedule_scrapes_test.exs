defmodule Instabot.Workers.ScheduleScrapesTest do
  use Instabot.DataCase, async: true
  use Oban.Testing, repo: Instabot.Repo

  import Ecto.Query
  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Instagram
  alias Instabot.Instagram.TrackedProfile
  alias Instabot.Repo
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

    test "enqueues profiles that have never been scraped" do
      user = user_fixture()
      profile = tracked_profile_fixture(user, %{instagram_username: "never_scraped", scrape_interval_minutes: 1440})

      assert :ok == ScheduleScrapes.perform(%Oban.Job{})

      assert_enqueued(worker: ScrapeProfile, args: %{tracked_profile_id: profile.id})
    end

    test "skips profiles until their scrape interval has elapsed" do
      user = user_fixture()
      due_profile = tracked_profile_fixture(user, %{instagram_username: "due_profile", scrape_interval_minutes: 360})

      skipped_profile =
        tracked_profile_fixture(user, %{instagram_username: "skipped_profile", scrape_interval_minutes: 360})

      now = DateTime.utc_now(:second)

      {1, nil} =
        Repo.update_all(
          from(profile in TrackedProfile, where: profile.id == ^due_profile.id),
          set: [last_scraped_at: DateTime.add(now, -361, :minute)]
        )

      {1, nil} =
        Repo.update_all(
          from(profile in TrackedProfile, where: profile.id == ^skipped_profile.id),
          set: [last_scraped_at: DateTime.add(now, -359, :minute)]
        )

      assert :ok == ScheduleScrapes.perform(%Oban.Job{})

      assert_enqueued(worker: ScrapeProfile, args: %{tracked_profile_id: due_profile.id})
      refute_enqueued(worker: ScrapeProfile, args: %{tracked_profile_id: skipped_profile.id})
    end
  end
end
