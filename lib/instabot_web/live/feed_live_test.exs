defmodule InstabotWeb.FeedLiveTest do
  use InstabotWeb.ConnCase, async: true

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures
  import Phoenix.LiveViewTest

  alias Instabot.Instagram.Events

  setup :register_and_log_in_user

  setup %{user: user} do
    profile = tracked_profile_fixture(user, %{instagram_username: "natgeo"})

    post =
      post_fixture(profile, %{
        caption: "mountain sunset",
        hashtags: ["nature", "travel"],
        media_urls: ["https://example.com/a.jpg", "https://example.com/b.jpg"]
      })

    %{profile: profile, post: post}
  end

  describe "mount" do
    test "renders posts for the current user", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/feed")

      assert html =~ "Feed"
      assert html =~ "natgeo"
      assert html =~ "mountain sunset"
    end

    test "shows empty state when a user has no posts" do
      other_conn = log_in_user(build_conn(), user_fixture())

      {:ok, _view, html} = live(other_conn, ~p"/feed")

      assert html =~ "No posts yet"
    end

    test "renders profile avatar images when available", %{conn: conn, user: user} do
      profile =
        tracked_profile_fixture(user, %{
          instagram_username: "avatarprofile",
          profile_pic_url: "https://cdn.instagram.com/avatar.jpg"
        })

      _post = post_fixture(profile, %{caption: "avatar post", instagram_post_id: "avatar_post"})

      {:ok, _view, html} = live(conn, ~p"/feed")

      assert html =~ "https://cdn.instagram.com/avatar.jpg"
      assert html =~ "avatarprofile"
    end

    test "shows Instagram caption date before scrape timestamp", %{conn: conn, profile: profile} do
      _post =
        post_fixture(profile, %{
          instagram_post_id: "caption_date_post",
          caption: "1,762 likes, 70 comments - natgeo on October 5, 2023: &quot;Sometimes...&quot;",
          posted_at: ~U[2023-10-05 12:00:00Z]
        })

      {:ok, _view, html} = live(conn, ~p"/feed")

      assert html =~ "Oct 05, 2023"
    end

    test "trims scraped metadata from quoted captions", %{conn: conn, profile: profile} do
      _post =
        post_fixture(profile, %{
          instagram_post_id: "quoted_caption_post",
          caption: "1,762 likes, 70 comments - natgeo on October 5, 2023: &quot;Sometimes...&quot;"
        })

      {:ok, _view, html} = live(conn, ~p"/feed")

      assert html =~ "Sometimes..."
      refute html =~ "1,762 likes"
    end

    test "decodes escaped Instagram caption entities", %{conn: conn, profile: profile} do
      _post =
        post_fixture(profile, %{
          instagram_post_id: "escaped_caption_post",
          caption: "1,762 likes, 70 comments - natgeo on October 5, 2023: &quot;Donald Glover &amp; friends&quot;."
        })

      {:ok, _view, html} = live(conn, ~p"/feed")

      assert html =~ "Donald Glover &amp; friends"
      refute html =~ "&amp;amp;"
      refute html =~ "&amp;quot"
    end
  end

  describe "search" do
    test "filters posts by caption", %{conn: conn, profile: profile} do
      _other =
        post_fixture(profile, %{
          caption: "something unrelated",
          instagram_post_id: "other_search"
        })

      {:ok, view, _html} = live(conn, ~p"/feed")

      html =
        view
        |> form("#search-form", %{"search" => "mountain"})
        |> render_change()

      assert html =~ "mountain sunset"
      refute html =~ "something unrelated"
    end

    test "filters posts by hashtag", %{conn: conn, profile: profile} do
      _other =
        post_fixture(profile, %{
          caption: "nothing",
          hashtags: ["other"],
          instagram_post_id: "other_hashtag"
        })

      {:ok, view, _html} = live(conn, ~p"/feed")

      html =
        view
        |> form("#search-form", %{"search" => "travel"})
        |> render_change()

      assert html =~ "mountain sunset"
      refute html =~ "nothing"
    end

    test "empty search with no matches shows No matches state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/feed")

      html =
        view
        |> form("#search-form", %{"search" => "zzznomatch"})
        |> render_change()

      assert html =~ "No matches"
      assert html =~ "Try clearing the filter"
    end
  end

  describe "profile filter" do
    test "filters to posts from the selected profile", %{conn: conn, user: user, profile: profile} do
      profile_b = tracked_profile_fixture(user, %{instagram_username: "nasa"})
      _post_b = post_fixture(profile_b, %{caption: "planet earth"})

      {:ok, view, html} = live(conn, ~p"/feed")
      assert html =~ "mountain sunset"
      assert html =~ "planet earth"

      html =
        view
        |> form("#profile-filter", %{"profile_id" => profile.id})
        |> render_change()

      assert html =~ "mountain sunset"
      refute html =~ "planet earth"
    end
  end

  describe "PubSub instagram_event" do
    test "refreshes posts when a new post is created", %{conn: conn, profile: profile} do
      {:ok, view, _html} = live(conn, ~p"/feed")

      post =
        post_fixture(profile, %{
          instagram_post_id: "fresh_pubsub_post",
          caption: "fresh websocket post"
        })

      Events.broadcast_post_created(profile, post)

      assert has_element?(view, "#post-#{post.id}")
    end
  end

  describe "infinite scroll" do
    test "renders sentinel when more posts exist and removes it when exhausted",
         %{conn: conn, profile: profile} do
      for index <- 1..30 do
        post_fixture(profile, %{
          caption: "extra #{index}",
          instagram_post_id: "extra_#{index}"
        })
      end

      {:ok, view, html} = live(conn, ~p"/feed")
      assert html =~ "posts-sentinel"
      assert html =~ "InstabotWeb.FeedLive.InfiniteScroll"

      html = render_click(view, "load_more")
      refute html =~ "posts-sentinel"
    end
  end

  describe "post modal" do
    test "opens modal on patch to /feed/posts/:id", %{conn: conn, post: post} do
      {:ok, view, _html} = live(conn, ~p"/feed")

      html =
        view
        |> element("#post-#{post.id}")
        |> render_click()

      assert html =~ "post-modal"
      assert html =~ "mountain sunset"
      assert html =~ "1 / 2"
      assert html =~ "#nature"
      assert html =~ "#travel"
      assert_patched(view, ~p"/feed/posts/#{post.id}")
    end

    test "direct navigation to /feed/posts/:id mounts with modal open", %{conn: conn, post: post} do
      {:ok, _view, html} = live(conn, ~p"/feed/posts/#{post.id}")

      assert html =~ "post-modal"
      assert html =~ "mountain sunset"
      assert html =~ "InstabotWeb.FeedLive.Lightbox"
    end

    test "next/prev image navigation works within the carousel", %{conn: conn, post: post} do
      {:ok, view, _html} = live(conn, ~p"/feed/posts/#{post.id}")

      html = render_click(view, "next_image")
      assert html =~ "2 / 2"

      html = render_click(view, "prev_image")
      assert html =~ "1 / 2"
    end

    test "closing the modal patches back to /feed", %{conn: conn, post: post} do
      {:ok, view, _html} = live(conn, ~p"/feed/posts/#{post.id}")

      view
      |> element("#post-modal a[aria-label='Close']")
      |> render_click()

      assert_patched(view, ~p"/feed")
      refute render(view) =~ "post-modal"
    end

    test "accessing another user's post raises NoResultsError (404)", %{conn: conn} do
      other_user = user_fixture()
      other_profile = tracked_profile_fixture(other_user)
      other_post = post_fixture(other_profile)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/feed/posts/#{other_post.id}")
      end
    end
  end
end
