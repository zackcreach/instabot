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
end
