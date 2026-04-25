defmodule InstabotWeb.DashboardLiveTest do
  use InstabotWeb.ConnCase, async: true
  use Oban.Testing, repo: Instabot.Repo

  import Instabot.InstagramFixtures
  import Phoenix.LiveViewTest

  alias Instabot.Workers.ScrapeProfile

  setup :register_and_log_in_user

  setup %{user: user} do
    profile = tracked_profile_fixture(user, %{instagram_username: "natgeo"})
    %{profile: profile}
  end

  describe "scrape_now event" do
    test "enqueues a scrape job for the profile", %{conn: conn, profile: profile} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("button[phx-click=scrape_now][phx-value-id=#{profile.id}]")
      |> render_click()

      assert_enqueued(worker: ScrapeProfile, args: %{tracked_profile_id: profile.id})
      assert render(view) =~ "Scrape queued for @natgeo"
    end
  end

  describe "scrape_all event" do
    test "enqueues scrape jobs for all active profiles", %{conn: conn, user: user, profile: profile} do
      profile2 = tracked_profile_fixture(user, %{instagram_username: "nasa"})

      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("button[phx-click=scrape_all]")
      |> render_click()

      assert_enqueued(worker: ScrapeProfile, args: %{tracked_profile_id: profile.id})
      assert_enqueued(worker: ScrapeProfile, args: %{tracked_profile_id: profile2.id})
      assert render(view) =~ "2 scrape jobs queued"
    end

    test "uses singular grammar when exactly one job is queued", %{conn: conn, profile: profile} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> element("button[phx-click=scrape_all]")
      |> render_click()

      assert_enqueued(worker: ScrapeProfile, args: %{tracked_profile_id: profile.id})
      assert render(view) =~ "1 scrape job queued."
      refute render(view) =~ "1 scrape jobs queued"
    end
  end

  describe "scrape_all button visibility" do
    test "is hidden when every profile is paused", %{conn: conn, profile: profile} do
      {:ok, _paused} = Instabot.Instagram.toggle_active(profile)

      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "button[phx-click=scrape_all]")
    end

    test "is visible when at least one profile is active", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "button[phx-click=scrape_all]")
    end
  end

  describe "PubSub scrape_completed" do
    test "refreshes data when scrape completes", %{conn: conn, user: user, profile: profile} do
      {:ok, view, _html} = live(conn, ~p"/")

      Phoenix.PubSub.broadcast(
        Instabot.PubSub,
        "scrape_updates:#{user.id}",
        {:scrape_completed, profile.id}
      )

      html = render(view)
      assert html =~ "natgeo"
    end
  end
end
