defmodule Instabot.Instagram.FeedTest do
  use Instabot.DataCase, async: true

  import Ecto.Query
  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Ecto.Association.NotLoaded
  alias Instabot.Instagram.Feed
  alias Instabot.Repo

  setup do
    user = user_fixture()
    other_user = user_fixture()
    %{user: user, other_user: other_user}
  end

  describe "list_posts/2" do
    test "returns only posts belonging to the user's tracked profiles", %{user: user, other_user: other_user} do
      profile = tracked_profile_fixture(user)
      other_profile = tracked_profile_fixture(other_user)

      own_post = post_fixture(profile)
      _other_post = post_fixture(other_profile)

      assert [returned] = Feed.list_posts(user.id)
      assert own_post.id == returned.id
    end

    test "orders by posted_at descending, ties broken by inserted_at desc", %{user: user} do
      profile = tracked_profile_fixture(user)
      now = DateTime.utc_now(:second)

      older_post = post_fixture(profile, %{posted_at: DateTime.add(now, -3600, :second)})
      newer_post = post_fixture(profile, %{posted_at: now})

      assert [first, second] = Feed.list_posts(user.id)
      assert newer_post.id == first.id
      assert older_post.id == second.id
    end

    test "orders posts without posted_at after dated posts", %{user: user} do
      profile = tracked_profile_fixture(user)
      now = DateTime.utc_now(:second)

      old_dated_post = post_fixture(profile, %{posted_at: DateTime.add(now, -365, :day)})
      recent_undated_post = post_fixture(profile, %{posted_at: nil})

      {1, nil} =
        Repo.update_all(
          from(p in Instabot.Instagram.Post, where: p.id == ^recent_undated_post.id),
          set: [inserted_at: now]
        )

      assert [first, second] = Feed.list_posts(user.id)
      assert old_dated_post.id == first.id
      assert recent_undated_post.id == second.id
    end

    test "filters by profile_id", %{user: user} do
      profile_a = tracked_profile_fixture(user, %{instagram_username: "alpha"})
      profile_b = tracked_profile_fixture(user, %{instagram_username: "bravo"})

      _post_a = post_fixture(profile_a)
      post_b = post_fixture(profile_b)

      assert [returned] = Feed.list_posts(user.id, profile_id: profile_b.id)
      assert post_b.id == returned.id
    end

    test "returns all posts when profile_id is blank string", %{user: user} do
      profile = tracked_profile_fixture(user)
      post = post_fixture(profile)

      assert [returned] = Feed.list_posts(user.id, profile_id: "")
      assert post.id == returned.id
    end

    test "excludes posts without media or captions", %{user: user} do
      profile = tracked_profile_fixture(user)

      visible_post = post_fixture(profile)

      _empty_post =
        post_fixture(profile, %{
          instagram_post_id: "empty_post",
          caption: "",
          media_urls: []
        })

      assert [returned] = Feed.list_posts(user.id)
      assert visible_post.id == returned.id
    end

    test "filters by search in caption", %{user: user} do
      profile = tracked_profile_fixture(user)

      _other = post_fixture(profile, %{caption: "something unrelated"})
      matching = post_fixture(profile, %{caption: "hello WORLD sunset"})

      assert [returned] = Feed.list_posts(user.id, search: "world")
      assert matching.id == returned.id
    end

    test "filters by search in hashtags", %{user: user} do
      profile = tracked_profile_fixture(user)

      _other = post_fixture(profile, %{hashtags: ["other"], caption: "nothing"})
      matching = post_fixture(profile, %{hashtags: ["travelDiary"], caption: "nothing"})

      assert [returned] = Feed.list_posts(user.id, search: "travel")
      assert matching.id == returned.id
    end

    test "respects limit and offset", %{user: user} do
      profile = tracked_profile_fixture(user)
      now = DateTime.utc_now(:second)

      posts =
        for index <- 0..4 do
          post_fixture(profile, %{posted_at: DateTime.add(now, index, :second)})
        end

      [_, _, _, _, newest] = posts

      assert [first] = Feed.list_posts(user.id, limit: 1)
      assert newest.id == first.id

      assert 3 == length(Feed.list_posts(user.id, limit: 3))
      assert 2 == length(Feed.list_posts(user.id, limit: 2, offset: 3))
    end

    test "preloads post_images and tracked_profile", %{user: user} do
      profile = tracked_profile_fixture(user)
      _post = post_fixture(profile)

      assert [returned] = Feed.list_posts(user.id)
      refute match?(%NotLoaded{}, returned.post_images)
      refute match?(%NotLoaded{}, returned.tracked_profile)
    end
  end

  describe "count_posts/2" do
    test "counts posts matching filters and ignores limit/offset", %{user: user} do
      profile = tracked_profile_fixture(user)
      for _ <- 1..5, do: post_fixture(profile)

      assert 5 == Feed.count_posts(user.id)
      assert 5 == Feed.count_posts(user.id, limit: 2, offset: 3)
    end

    test "count respects profile filter", %{user: user} do
      profile_a = tracked_profile_fixture(user, %{instagram_username: "alpha"})
      profile_b = tracked_profile_fixture(user, %{instagram_username: "bravo"})

      for _ <- 1..3, do: post_fixture(profile_a)
      for _ <- 1..2, do: post_fixture(profile_b)

      assert 3 == Feed.count_posts(user.id, profile_id: profile_a.id)
    end

    test "count excludes posts without media or captions", %{user: user} do
      profile = tracked_profile_fixture(user)

      _visible_post = post_fixture(profile)

      _empty_post =
        post_fixture(profile, %{
          instagram_post_id: "empty_count_post",
          caption: "",
          media_urls: []
        })

      assert 1 == Feed.count_posts(user.id)
    end
  end

  describe "get_post_for_user!/2" do
    test "returns the post when it belongs to the user with preloads", %{user: user} do
      profile = tracked_profile_fixture(user)
      post = post_fixture(profile)

      returned = Feed.get_post_for_user!(user.id, post.id)

      assert post.id == returned.id
      refute match?(%NotLoaded{}, returned.post_images)
      refute match?(%NotLoaded{}, returned.tracked_profile)
    end

    test "raises when the post belongs to another user", %{user: user, other_user: other_user} do
      other_profile = tracked_profile_fixture(other_user)
      other_post = post_fixture(other_profile)

      assert_raise Ecto.NoResultsError, fn ->
        Feed.get_post_for_user!(user.id, other_post.id)
      end
    end
  end

  describe "list_stories/2" do
    test "scopes stories to user's tracked profiles", %{user: user, other_user: other_user} do
      profile = tracked_profile_fixture(user)
      other_profile = tracked_profile_fixture(other_user)

      own_story = story_fixture(profile)
      _other_story = story_fixture(other_profile)

      assert [returned] = Feed.list_stories(user.id)
      assert own_story.id == returned.id
    end

    test "orders by posted_at descending", %{user: user} do
      profile = tracked_profile_fixture(user)
      now = DateTime.utc_now(:second)

      older = story_fixture(profile, %{posted_at: DateTime.add(now, -3600, :second)})
      newer = story_fixture(profile, %{posted_at: now})

      assert [first, second] = Feed.list_stories(user.id)
      assert newer.id == first.id
      assert older.id == second.id
    end

    test "filters by profile_id", %{user: user} do
      profile_a = tracked_profile_fixture(user, %{instagram_username: "alpha"})
      profile_b = tracked_profile_fixture(user, %{instagram_username: "bravo"})

      _story_a = story_fixture(profile_a)
      story_b = story_fixture(profile_b)

      assert [returned] = Feed.list_stories(user.id, profile_id: profile_b.id)
      assert story_b.id == returned.id
    end

    test "respects limit and offset", %{user: user} do
      profile = tracked_profile_fixture(user)
      for _ <- 1..5, do: story_fixture(profile)

      assert 2 == length(Feed.list_stories(user.id, limit: 2))
      assert 3 == length(Feed.list_stories(user.id, limit: 3, offset: 2))
    end
  end

  describe "count_stories/2" do
    test "returns count for user's stories", %{user: user} do
      profile = tracked_profile_fixture(user)
      for _ <- 1..4, do: story_fixture(profile)

      assert 4 == Feed.count_stories(user.id)
    end
  end

  describe "get_story_for_user!/2" do
    test "returns the story when it belongs to the user", %{user: user} do
      profile = tracked_profile_fixture(user)
      story = story_fixture(profile)

      returned = Feed.get_story_for_user!(user.id, story.id)

      assert story.id == returned.id
      refute match?(%NotLoaded{}, returned.tracked_profile)
    end

    test "raises when the story belongs to another user", %{user: user, other_user: other_user} do
      other_profile = tracked_profile_fixture(other_user)
      other_story = story_fixture(other_profile)

      assert_raise Ecto.NoResultsError, fn ->
        Feed.get_story_for_user!(user.id, other_story.id)
      end
    end
  end
end
