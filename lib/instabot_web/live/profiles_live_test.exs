defmodule InstabotWeb.ProfilesLiveTest do
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
      {:ok, view, _html} = live(conn, ~p"/profiles")

      view
      |> element("button[phx-click=scrape_now][phx-value-id=#{profile.id}]")
      |> render_click()

      assert_enqueued(worker: ScrapeProfile, args: %{tracked_profile_id: profile.id})
      assert render(view) =~ "Scrape queued for @natgeo"
    end
  end

  describe "PubSub scrape_completed" do
    test "refreshes profiles when scrape completes", %{conn: conn, user: user, profile: profile} do
      {:ok, view, _html} = live(conn, ~p"/profiles")

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
