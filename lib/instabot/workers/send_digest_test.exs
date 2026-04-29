defmodule Instabot.Workers.SendDigestTest do
  use Instabot.DataCase, async: true

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Instagram
  alias Instabot.Notifications
  alias Instabot.Workers.SendDigest

  setup do
    user = user_fixture()
    profile = tracked_profile_fixture(user)
    _preference = Notifications.get_or_create_preference(user.id)
    %{user: user, profile: profile}
  end

  describe "perform/1" do
    test "skips when no new content exists", %{user: user} do
      assert :ok ==
               SendDigest.perform(%Oban.Job{
                 args: %{"user_id" => user.id, "digest_type" => "daily"}
               })

      assert nil == Notifications.last_digest_for_user(user.id, "daily")
    end

    test "sends digest and creates record when posts exist", %{user: user, profile: profile} do
      {:ok, _post} =
        Instagram.create_post(profile.id, %{
          instagram_post_id: "digest_post_#{System.unique_integer([:positive])}",
          post_type: "image",
          caption: "Test post for digest",
          media_urls: []
        })

      assert :ok ==
               SendDigest.perform(%Oban.Job{
                 args: %{"user_id" => user.id, "digest_type" => "daily"}
               })

      digest = Notifications.last_digest_for_user(user.id, "daily")
      assert %{digest_type: "daily", posts_count: 1, stories_count: 0} = digest
      assert digest.sent_at
      assert digest.period_start
      assert digest.period_end
    end

    test "sends digest when stories exist", %{user: user, profile: profile} do
      {:ok, _story} =
        Instagram.create_story(profile.id, %{
          instagram_story_id: "digest_story_#{System.unique_integer([:positive])}",
          story_type: "image",
          ocr_status: "completed"
        })

      assert :ok ==
               SendDigest.perform(%Oban.Job{
                 args: %{"user_id" => user.id, "digest_type" => "weekly"}
               })

      digest = Notifications.last_digest_for_user(user.id, "weekly")
      assert %{digest_type: "weekly", posts_count: 0, stories_count: 1} = digest
    end

    test "profile-scoped digest only includes that profile", %{user: user, profile: profile} do
      other_profile = tracked_profile_fixture(user)

      for tracked_profile <- [profile, other_profile] do
        {:ok, _post} =
          Instagram.create_post(tracked_profile.id, %{
            instagram_post_id: "profile_digest_post_#{tracked_profile.id}",
            post_type: "image",
            caption: "Profile scoped digest",
            media_urls: []
          })
      end

      assert :ok ==
               SendDigest.perform(%Oban.Job{
                 args: %{
                   "user_id" => user.id,
                   "digest_type" => "daily",
                   "tracked_profile_id" => profile.id
                 }
               })

      digest = Notifications.last_digest_for_profile(user.id, "daily", profile.id)
      assert %{digest_type: "daily", posts_count: 1, stories_count: 0} = digest
      assert nil == Notifications.last_digest_for_profile(user.id, "daily", other_profile.id)
    end

    test "skips digest when only likely ad stories exist", %{user: user, profile: profile} do
      {:ok, _story} =
        Instagram.create_story(profile.id, %{
          instagram_story_id: "ad_digest_story_#{System.unique_integer([:positive])}",
          story_type: "video",
          story_chrome_detected: false
        })

      assert :ok ==
               SendDigest.perform(%Oban.Job{
                 args: %{"user_id" => user.id, "digest_type" => "daily"}
               })

      assert nil == Notifications.last_digest_for_user(user.id, "daily")
    end

    test "runs pending story OCR before sending digest", %{user: user, profile: profile} do
      {:ok, _story} =
        Instagram.create_story(profile.id, %{
          instagram_story_id: "pending_ocr_story_#{System.unique_integer([:positive])}",
          story_type: "image",
          screenshot_path: "/tmp/pending_ocr_story.png",
          ocr_status: "pending"
        })

      assert :ok ==
               SendDigest.perform(%Oban.Job{
                 args: %{"user_id" => user.id, "digest_type" => "daily"}
               })

      assert %{digest_type: "daily", stories_count: 1} = Notifications.last_digest_for_user(user.id, "daily")
    end

    test "sends digest with pending OCR when OCR is excluded", %{user: user, profile: profile} do
      preference = Notifications.get_or_create_preference(user.id)
      {:ok, _preference} = Notifications.update_preference(preference, %{include_ocr: false})

      {:ok, _story} =
        Instagram.create_story(profile.id, %{
          instagram_story_id: "excluded_ocr_story_#{System.unique_integer([:positive])}",
          story_type: "image",
          screenshot_path: "/tmp/excluded_ocr_story.png",
          ocr_status: "pending"
        })

      assert :ok ==
               SendDigest.perform(%Oban.Job{
                 args: %{"user_id" => user.id, "digest_type" => "daily"}
               })

      assert %{digest_type: "daily", stories_count: 1} = Notifications.last_digest_for_user(user.id, "daily")
    end

    test "uses previous digest period_end as new period_start", %{user: user, profile: profile} do
      past = DateTime.add(DateTime.utc_now(:second), -3600, :second)

      {:ok, _prev_digest} =
        Notifications.create_email_digest(user.id, %{
          digest_type: "daily",
          posts_count: 0,
          stories_count: 0,
          sent_at: past,
          period_start: DateTime.add(past, -86_400, :second),
          period_end: past
        })

      {:ok, _post} =
        Instagram.create_post(profile.id, %{
          instagram_post_id: "period_post_#{System.unique_integer([:positive])}",
          post_type: "image",
          media_urls: []
        })

      assert :ok ==
               SendDigest.perform(%Oban.Job{
                 args: %{"user_id" => user.id, "digest_type" => "daily"}
               })

      digest = Notifications.last_digest_for_user(user.id, "daily")
      assert DateTime.compare(digest.period_start, past) == :eq
    end
  end
end
