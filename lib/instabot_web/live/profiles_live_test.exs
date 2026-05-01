defmodule InstabotWeb.ProfilesLiveTest do
  use InstabotWeb.ConnCase, async: true
  use Oban.Testing, repo: Instabot.Repo

  import Ecto.Query
  import Instabot.InstagramFixtures
  import Phoenix.LiveViewTest

  alias Instabot.Instagram.TrackedProfile
  alias Instabot.Repo
  alias Instabot.Scraping.Events
  alias Instabot.Workers.ScrapeProfile

  setup :register_and_log_in_user

  setup %{user: user} do
    profile = tracked_profile_fixture(user, %{instagram_username: "natgeo"})
    %{profile: profile}
  end

  describe "mount" do
    test "renders last scraped timestamps in Eastern time", %{conn: conn, profile: profile} do
      last_scraped_at = ~U[2026-04-25 02:01:00Z]

      {1, nil} =
        Repo.update_all(
          from(p in TrackedProfile, where: p.id == ^profile.id),
          set: [last_scraped_at: last_scraped_at]
        )

      {:ok, _view, html} = live(conn, ~p"/profiles")

      assert html =~ "Apr 24, 2026 10:01 PM"
    end

    test "renders scrape interval controls", %{conn: conn, profile: profile} do
      {:ok, view, _html} = live(conn, ~p"/profiles")

      assert has_element?(view, "#profile-scrape-interval-form-#{profile.id}")
      assert has_element?(view, "#profile-scrape-interval-#{profile.id}")
    end
  end

  describe "save_profile event" do
    test "enqueues a scrape job for the newly added profile", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/profiles")

      view
      |> element("button[phx-click=show_form]")
      |> render_click()

      view
      |> form("#add_profile_form", %{
        "tracked_profile" => %{
          "instagram_username" => "newprofile",
          "display_name" => "New Profile"
        }
      })
      |> render_submit()

      profile = Repo.get_by!(TrackedProfile, user_id: user.id, instagram_username: "newprofile")

      assert_enqueued(worker: ScrapeProfile, args: %{tracked_profile_id: profile.id})
      assert has_element?(view, "#profile-scrape-state-#{profile.id}", "Queued")
      assert render(view) =~ "Profile @newprofile added and scrape queued."
    end
  end

  describe "scrape_now event" do
    test "enqueues a scrape job for the profile", %{conn: conn, profile: profile} do
      {:ok, view, _html} = live(conn, ~p"/profiles")

      view
      |> element("button[phx-click=scrape_now][phx-value-id=#{profile.id}]")
      |> render_click()

      assert_enqueued(worker: ScrapeProfile, args: %{tracked_profile_id: profile.id})
      assert render(view) =~ "Scrape queued for @natgeo"
      assert render(view) =~ "Queued"
    end

    test "persists queued scrape state after refresh", %{conn: conn, profile: profile} do
      {:ok, view, _html} = live(conn, ~p"/profiles")

      view
      |> element("button[phx-click=scrape_now][phx-value-id=#{profile.id}]")
      |> render_click()

      {:ok, view, _html} = live(conn, ~p"/profiles")

      assert has_element?(view, "#profile-scrape-state-#{profile.id}", "Queued")
    end

    test "persists completed scrape state after refresh", %{conn: conn, profile: profile} do
      {:ok, job} =
        %{tracked_profile_id: profile.id}
        |> ScrapeProfile.new()
        |> Oban.insert()

      {1, nil} =
        Repo.update_all(
          from(job in Oban.Job, where: job.id == ^job.id),
          set: [state: "completed"]
        )

      {:ok, view, _html} = live(conn, ~p"/profiles")

      assert has_element?(view, "#profile-scrape-state-#{profile.id}", "Scrape complete")
    end
  end

  describe "update_scrape_interval event" do
    test "updates the profile scrape interval", %{conn: conn, profile: profile} do
      {:ok, view, _html} = live(conn, ~p"/profiles")

      view
      |> form("#profile-scrape-interval-form-#{profile.id}", %{
        "tracked_profile" => %{"scrape_interval_minutes" => "360"}
      })
      |> render_change()

      profile = Repo.get!(TrackedProfile, profile.id)

      assert 360 == profile.scrape_interval_minutes
      assert render(view) =~ "Scrape interval updated for @natgeo."
    end
  end

  describe "PubSub scrape_event" do
    test "refreshes profiles when scrape completes", %{conn: conn, profile: profile} do
      {:ok, view, _html} = live(conn, ~p"/profiles")

      Events.broadcast(profile, :completed)

      html = render(view)
      assert html =~ "natgeo"
      assert html =~ "Scrape complete"
    end

    test "renders failed scrape state", %{conn: conn, profile: profile} do
      {:ok, view, _html} = live(conn, ~p"/profiles")

      Events.broadcast(profile, :failed, %{message: "Scrape failed"})

      html = render(view)
      assert html =~ "Scrape failed"
    end
  end
end
