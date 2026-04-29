defmodule Instabot.Workers.SendImmediateNotificationTest do
  use Instabot.DataCase, async: true

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Instagram
  alias Instabot.Notifications
  alias Instabot.Workers.SendImmediateNotification

  setup do
    user = user_fixture()
    profile = tracked_profile_fixture(user)
    %{user: user, profile: profile}
  end

  describe "perform/1" do
    test "skips when user has no preference", %{user: user} do
      assert :ok ==
               SendImmediateNotification.perform(%Oban.Job{
                 args: %{"user_id" => user.id}
               })
    end

    test "skips when frequency is not immediate", %{user: user} do
      pref = Notifications.get_or_create_preference(user.id)
      {:ok, _} = Notifications.update_preference(pref, %{frequency: "daily"})

      assert :ok ==
               SendImmediateNotification.perform(%Oban.Job{
                 args: %{"user_id" => user.id}
               })
    end

    test "skips when no new content", %{user: user} do
      pref = Notifications.get_or_create_preference(user.id)
      {:ok, _} = Notifications.update_preference(pref, %{frequency: "immediate"})

      assert :ok ==
               SendImmediateNotification.perform(%Oban.Job{
                 args: %{"user_id" => user.id}
               })

      assert nil == Notifications.last_digest_for_user(user.id, "immediate")
    end

    test "sends notification and records digest when content exists", %{user: user, profile: profile} do
      pref = Notifications.get_or_create_preference(user.id)
      {:ok, _} = Notifications.update_preference(pref, %{frequency: "immediate"})

      {:ok, _post} =
        Instagram.create_post(profile.id, %{
          instagram_post_id: "imm_post_#{System.unique_integer([:positive])}",
          post_type: "image",
          caption: "Immediate notification test",
          media_urls: []
        })

      assert :ok ==
               SendImmediateNotification.perform(%Oban.Job{
                 args: %{"user_id" => user.id}
               })

      digest = Notifications.last_digest_for_user(user.id, "immediate")
      assert %{digest_type: "immediate", posts_count: 1, stories_count: 0} = digest
    end

    test "profile-scoped notification excludes other profile content", %{user: user, profile: profile} do
      other_profile = tracked_profile_fixture(user)
      user_preference = Notifications.get_or_create_preference(user.id)
      {:ok, _user_preference} = Notifications.update_preference(user_preference, %{frequency: "disabled"})
      profile_preference = Notifications.get_or_create_profile_preference(user.id, profile.id)
      {:ok, _profile_preference} = Notifications.update_profile_preference(profile_preference, %{frequency: "immediate"})

      {:ok, _post} =
        Instagram.create_post(profile.id, %{
          instagram_post_id: "scoped_imm_post_#{System.unique_integer([:positive])}",
          post_type: "image",
          caption: "Scoped immediate notification test",
          media_urls: []
        })

      {:ok, _other_post} =
        Instagram.create_post(other_profile.id, %{
          instagram_post_id: "other_scoped_imm_post_#{System.unique_integer([:positive])}",
          post_type: "image",
          caption: "Other profile content",
          media_urls: []
        })

      assert :ok ==
               SendImmediateNotification.perform(%Oban.Job{
                 args: %{"user_id" => user.id, "tracked_profile_id" => profile.id}
               })

      digest = Notifications.last_digest_for_profile(user.id, "immediate", profile.id)
      assert %{digest_type: "immediate", posts_count: 1, stories_count: 0} = digest
      assert nil == Notifications.last_digest_for_profile(user.id, "immediate", other_profile.id)
    end

    test "waits for OCR completion event while story OCR is pending", %{user: user, profile: profile} do
      pref = Notifications.get_or_create_preference(user.id)
      {:ok, _preference} = Notifications.update_preference(pref, %{frequency: "immediate"})

      {:ok, _story} =
        Instagram.create_story(profile.id, %{
          instagram_story_id: "imm_pending_ocr_story_#{System.unique_integer([:positive])}",
          story_type: "image",
          screenshot_path: "/tmp/imm_pending_ocr_story.png",
          ocr_status: "pending"
        })

      assert :ok ==
               SendImmediateNotification.perform(%Oban.Job{
                 args: %{"user_id" => user.id}
               })

      assert nil == Notifications.last_digest_for_user(user.id, "immediate")
    end
  end
end
