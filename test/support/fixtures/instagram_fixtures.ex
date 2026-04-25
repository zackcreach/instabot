defmodule Instabot.InstagramFixtures do
  @moduledoc """
  Test helpers for creating Instagram-related entities.
  """

  alias Instabot.Encryption
  alias Instabot.Instagram

  def unique_username, do: "testuser#{System.unique_integer([:positive])}"

  def instagram_connection_fixture(user, attrs \\ %{}) do
    connection_attrs =
      Enum.into(attrs, %{
        instagram_username: unique_username(),
        status: "connected"
      })

    {:ok, connection} = Instagram.create_connection(user.id, connection_attrs)
    connection
  end

  def connected_connection_fixture(user, attrs \\ %{}) do
    connection = instagram_connection_fixture(user, attrs)
    encrypted = Encryption.encrypt_term(sample_cookies())
    expires_at = DateTime.add(DateTime.utc_now(), 90, :day)
    {:ok, connection} = Instagram.store_cookies(connection, encrypted, expires_at)
    connection
  end

  def tracked_profile_fixture(user, attrs \\ %{}) do
    profile_attrs =
      Enum.into(attrs, %{
        instagram_username: unique_username(),
        display_name: "Test Profile"
      })

    {:ok, profile} = Instagram.create_tracked_profile(user.id, profile_attrs)
    profile
  end

  def post_fixture(tracked_profile, attrs \\ %{}) do
    post_attrs =
      Enum.into(attrs, %{
        instagram_post_id: "post_#{System.unique_integer([:positive])}",
        post_type: "image",
        caption: "Sample caption",
        hashtags: [],
        media_urls: ["https://example.com/image.jpg"],
        permalink: "https://instagram.com/p/sample",
        posted_at: DateTime.utc_now(:second)
      })

    {:ok, post} = Instagram.create_post(tracked_profile.id, post_attrs)
    post
  end

  def story_fixture(tracked_profile, attrs \\ %{}) do
    now = DateTime.utc_now(:second)

    story_attrs =
      Enum.into(attrs, %{
        instagram_story_id: "story_#{System.unique_integer([:positive])}",
        story_type: "image",
        ocr_status: "completed",
        ocr_text: "Sample OCR text",
        screenshot_path: "/tmp/screenshot.png",
        posted_at: now,
        expires_at: DateTime.add(now, 24, :hour)
      })

    {:ok, story} = Instagram.create_story(tracked_profile.id, story_attrs)
    story
  end

  def sample_cookies do
    [
      %{
        "name" => "sessionid",
        "value" => "test_session_#{System.unique_integer([:positive])}",
        "domain" => ".instagram.com",
        "path" => "/",
        "httpOnly" => true,
        "secure" => true
      },
      %{
        "name" => "csrftoken",
        "value" => "test_csrf_#{System.unique_integer([:positive])}",
        "domain" => ".instagram.com",
        "path" => "/",
        "httpOnly" => false,
        "secure" => true
      }
    ]
  end
end
