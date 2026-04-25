defmodule InstabotWeb.StoriesLiveTest do
  use InstabotWeb.ConnCase, async: true

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  setup %{user: user} do
    profile = tracked_profile_fixture(user, %{instagram_username: "natgeo"})
    story = story_fixture(profile, %{ocr_text: "breaking headline"})
    %{profile: profile, story: story}
  end

  describe "mount" do
    test "renders stories for the current user", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/feed/stories")

      assert html =~ "Stories"
      assert html =~ "natgeo"
      assert html =~ "breaking headline"
    end

    test "shows empty state when a user has no stories" do
      other_conn = log_in_user(build_conn(), user_fixture())

      {:ok, _view, html} = live(other_conn, ~p"/feed/stories")

      assert html =~ "No stories yet"
    end

    test "groups stories by day with a heading", %{conn: conn, profile: profile} do
      now = DateTime.utc_now(:second)
      two_days_ago = DateTime.add(now, -2 * 86_400, :second)

      _older =
        story_fixture(profile, %{
          ocr_text: "older story",
          posted_at: two_days_ago
        })

      {:ok, _view, html} = live(conn, ~p"/feed/stories")

      assert html =~ "breaking headline"
      assert html =~ "older story"
      assert html =~ Calendar.strftime(now, "%B %d, %Y")
      assert html =~ Calendar.strftime(two_days_ago, "%B %d, %Y")
    end
  end

  describe "profile filter" do
    test "filters stories to the selected profile", %{conn: conn, user: user, profile: profile} do
      profile_b = tracked_profile_fixture(user, %{instagram_username: "nasa"})
      _story_b = story_fixture(profile_b, %{ocr_text: "space news"})

      {:ok, view, html} = live(conn, ~p"/feed/stories")
      assert html =~ "breaking headline"
      assert html =~ "space news"

      html =
        view
        |> form("#profile-filter", %{"profile_id" => profile.id})
        |> render_change()

      assert html =~ "breaking headline"
      refute html =~ "space news"
    end
  end

  describe "infinite scroll" do
    test "renders sentinel when more stories exist and removes it when exhausted",
         %{conn: conn, profile: profile} do
      for index <- 1..30 do
        story_fixture(profile, %{ocr_text: "extra #{index}"})
      end

      {:ok, view, html} = live(conn, ~p"/feed/stories")
      assert html =~ "stories-sentinel"
      assert html =~ "InstabotWeb.StoriesLive.InfiniteScroll"

      html = render_click(view, "load_more")
      refute html =~ "stories-sentinel"
    end
  end

  describe "story modal" do
    test "opens modal on patch to /feed/stories/:id", %{conn: conn, story: story} do
      {:ok, view, _html} = live(conn, ~p"/feed/stories")

      html =
        view
        |> element("#story-#{story.id}")
        |> render_click()

      assert html =~ "story-modal"
      assert html =~ "breaking headline"
      assert html =~ "EXTRACTED TEXT"
      assert html =~ "InstabotWeb.StoriesLive.Lightbox"
      assert_patched(view, ~p"/feed/stories/#{story.id}")
    end

    test "closing the modal patches back to /feed/stories", %{conn: conn, story: story} do
      {:ok, view, _html} = live(conn, ~p"/feed/stories/#{story.id}")

      view
      |> element("#story-modal a[aria-label='Close']")
      |> render_click()

      assert_patched(view, ~p"/feed/stories")
      refute render(view) =~ "story-modal"
    end

    test "accessing another user's story raises NoResultsError (404)", %{conn: conn} do
      other_user = user_fixture()
      other_profile = tracked_profile_fixture(other_user)
      other_story = story_fixture(other_profile)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/feed/stories/#{other_story.id}")
      end
    end
  end
end
