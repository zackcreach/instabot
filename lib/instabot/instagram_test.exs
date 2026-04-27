defmodule Instabot.InstagramTest do
  use Instabot.DataCase, async: true

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Instagram
  alias Instabot.Instagram.Feed

  describe "upsert_post_from_scrape/2" do
    test "updates an existing shell post with scraped details" do
      user = user_fixture()
      profile = tracked_profile_fixture(user)

      shell_post =
        post_fixture(profile, %{
          instagram_post_id: "same_post",
          caption: nil,
          posted_at: nil,
          hashtags: [],
          media_urls: []
        })

      posted_at = DateTime.utc_now(:second)

      assert {:ok, updated_post, :updated} =
               Instagram.upsert_post_from_scrape(profile.id, %{
                 instagram_post_id: "same_post",
                 caption: "Restocked today #Vintage",
                 posted_at: posted_at,
                 post_type: "image",
                 hashtags: ["vintage"],
                 media_urls: ["https://example.com/restock.jpg"],
                 permalink: "https://instagram.com/p/same_post"
               })

      assert shell_post.id == updated_post.id
      assert "Restocked today #Vintage" == updated_post.caption
      assert posted_at == updated_post.posted_at
      assert ["vintage"] == updated_post.hashtags
      assert ["https://example.com/restock.jpg"] == updated_post.media_urls
      assert [visible_post] = Feed.list_posts(user.id, profile_id: profile.id)
      assert shell_post.id == visible_post.id
    end

    test "does not replace useful post details with blank scrape data" do
      user = user_fixture()
      profile = tracked_profile_fixture(user)
      posted_at = DateTime.utc_now(:second)

      post =
        post_fixture(profile, %{
          instagram_post_id: "rich_post",
          caption: "Existing caption",
          posted_at: posted_at,
          hashtags: ["existing"],
          media_urls: ["https://example.com/existing.jpg"],
          permalink: "https://instagram.com/p/rich_post"
        })

      assert {:ok, updated_post, :unchanged} =
               Instagram.upsert_post_from_scrape(profile.id, %{
                 instagram_post_id: "rich_post",
                 caption: nil,
                 posted_at: nil,
                 post_type: "image",
                 hashtags: [],
                 media_urls: [],
                 permalink: nil
               })

      assert post.id == updated_post.id
      assert "Existing caption" == updated_post.caption
      assert posted_at == updated_post.posted_at
      assert ["existing"] == updated_post.hashtags
      assert ["https://example.com/existing.jpg"] == updated_post.media_urls
      assert "https://instagram.com/p/rich_post" == updated_post.permalink
    end
  end

  describe "upsert_story_from_scrape/2" do
    test "updates an existing story with a refreshed screenshot path" do
      user = user_fixture()
      profile = tracked_profile_fixture(user)
      posted_at = DateTime.utc_now(:second)

      story =
        story_fixture(profile, %{
          instagram_story_id: "same_story",
          screenshot_path: "priv/static/screenshots/missing.png",
          media_url: nil,
          posted_at: posted_at
        })

      assert {:ok, updated_story, :updated} =
               Instagram.upsert_story_from_scrape(profile.id, %{
                 instagram_story_id: "same_story",
                 story_type: "image",
                 screenshot_path: "priv/static/screenshots/refreshed.png",
                 media_url: "https://example.com/story.jpg",
                 posted_at: posted_at,
                 expires_at: DateTime.add(posted_at, 1, :day)
               })

      assert story.id == updated_story.id
      assert "priv/static/screenshots/refreshed.png" == updated_story.screenshot_path
      assert "https://example.com/story.jpg" == updated_story.media_url
      assert "pending" == updated_story.ocr_status
      assert nil == updated_story.ocr_text
    end

    test "queues OCR again when a failed story gets a new screenshot" do
      user = user_fixture()
      profile = tracked_profile_fixture(user)
      posted_at = DateTime.utc_now(:second)

      story =
        story_fixture(profile, %{
          instagram_story_id: "failed_story",
          screenshot_path: "priv/static/screenshots/failed.png",
          ocr_status: "failed",
          ocr_text: nil,
          posted_at: posted_at
        })

      assert {:ok, updated_story, :updated} =
               Instagram.upsert_story_from_scrape(profile.id, %{
                 instagram_story_id: "failed_story",
                 story_type: "image",
                 screenshot_path: "priv/static/screenshots/retry.png",
                 posted_at: posted_at,
                 expires_at: DateTime.add(posted_at, 1, :day)
               })

      assert story.id == updated_story.id
      assert "pending" == updated_story.ocr_status
      assert [pending_story] = Instagram.get_stories_pending_ocr(profile.id)
      assert updated_story.id == pending_story.id
    end

    test "queues OCR again when a story gets a new hosted screenshot URL" do
      user = user_fixture()
      profile = tracked_profile_fixture(user)
      posted_at = DateTime.utc_now(:second)

      story =
        story_fixture(profile, %{
          instagram_story_id: "hosted_story",
          screenshot_path: nil,
          screenshot_url: "https://res.cloudinary.com/demo/image/upload/v1/stories/old.png",
          ocr_status: "completed",
          ocr_text: "old text",
          posted_at: posted_at
        })

      assert {:ok, updated_story, :updated} =
               Instagram.upsert_story_from_scrape(profile.id, %{
                 instagram_story_id: "hosted_story",
                 story_type: "image",
                 screenshot_url: "https://res.cloudinary.com/demo/image/upload/v1/stories/new.png",
                 posted_at: posted_at,
                 expires_at: DateTime.add(posted_at, 1, :day)
               })

      assert story.id == updated_story.id
      assert "https://res.cloudinary.com/demo/image/upload/v1/stories/new.png" == updated_story.screenshot_url
      assert "pending" == updated_story.ocr_status
      assert nil == updated_story.ocr_text
      assert [pending_story] = Instagram.get_stories_pending_ocr(profile.id)
      assert updated_story.id == pending_story.id
    end

    test "does not replace useful story details with blank scrape data" do
      user = user_fixture()
      profile = tracked_profile_fixture(user)

      story =
        story_fixture(profile, %{
          instagram_story_id: "rich_story",
          screenshot_path: "priv/static/screenshots/story.png",
          media_url: "https://example.com/story.jpg"
        })

      assert {:ok, updated_story, :unchanged} =
               Instagram.upsert_story_from_scrape(profile.id, %{
                 instagram_story_id: "rich_story",
                 story_type: "image",
                 screenshot_path: nil,
                 media_url: nil,
                 posted_at: nil,
                 expires_at: nil
               })

      assert story.id == updated_story.id
      assert "priv/static/screenshots/story.png" == updated_story.screenshot_path
      assert "https://example.com/story.jpg" == updated_story.media_url
    end
  end
end
