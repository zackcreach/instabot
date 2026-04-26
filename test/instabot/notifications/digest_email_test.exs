defmodule Instabot.Notifications.DigestEmailTest do
  use Instabot.DataCase, async: true

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Instagram
  alias Instabot.Notifications
  alias Instabot.Notifications.DigestEmail

  setup do
    user = user_fixture()
    profile = tracked_profile_fixture(user, %{instagram_username: "visual_digest"})
    preference = Notifications.get_or_create_preference(user.id)
    period_start = ~U[2026-04-25 17:35:00Z]
    period_end = ~U[2026-04-25 17:36:00Z]

    %{user: user, profile: profile, preference: preference, period_start: period_start, period_end: period_end}
  end

  test "renders post media previews in the html digest", context do
    post =
      context.profile
      |> post_fixture(%{
        media_urls: ["https://example.com/fallback.jpg"],
        caption: "Post with a downloaded preview"
      })
      |> Repo.preload(:tracked_profile)

    {:ok, _image} =
      Instagram.create_post_image(post.id, %{
        original_url: "https://example.com/original.jpg",
        local_path: "priv/static/uploads/posts/image_0.jpg",
        position: 0,
        content_type: "image/jpeg",
        file_size: 123
      })

    post = Repo.preload(post, [:post_images], force: true)

    email = build_email(context, %{posts: [post], stories: []})

    assert email.html_body =~ ~s(src="http://localhost:4000/uploads/posts/image_0.jpg")
    assert email.html_body =~ ~s(alt="Instagram post preview")
    refute email.html_body =~ "https://example.com/fallback.jpg"
  end

  test "renders story screenshots in the html digest", context do
    story =
      context.profile
      |> story_fixture(%{
        screenshot_path: "priv/static/screenshots/story.png",
        media_url: "https://example.com/story.jpg"
      })
      |> Repo.preload(:tracked_profile)

    email = build_email(context, %{posts: [], stories: [story]})

    assert email.html_body =~ ~s(src="http://localhost:4000/screenshots/story.png")
    assert email.html_body =~ ~s(alt="Instagram story screenshot")
    refute email.html_body =~ "https://example.com/story.jpg"
  end

  test "renders OCR processing status when story text is not ready", context do
    story =
      context.profile
      |> story_fixture(%{
        ocr_status: "pending",
        ocr_text: nil
      })
      |> Repo.preload(:tracked_profile)

    email = build_email(context, %{posts: [], stories: [story]})

    assert email.html_body =~ "OCR: pending"
    assert email.text_body =~ "OCR: pending"
  end

  test "renders digest period in Eastern time with daylight saving abbreviation", context do
    email = build_email(context, %{posts: [], stories: []})

    assert email.html_body =~ "2026-04-25 13:35 EDT – 2026-04-25 13:36 EDT"
    assert email.text_body =~ "Period: 2026-04-25 13:35 EDT – 2026-04-25 13:36 EDT"
    refute email.html_body =~ "UTC"
    refute email.text_body =~ "UTC"
  end

  test "renders standard Eastern time outside daylight saving", context do
    email =
      DigestEmail.build(context.user, context.preference, %{
        posts: [],
        stories: [],
        period_start: ~U[2026-01-15 17:35:00Z],
        period_end: ~U[2026-01-15 17:36:00Z]
      })

    assert email.html_body =~ "2026-01-15 12:35 EST – 2026-01-15 12:36 EST"
    assert email.text_body =~ "Period: 2026-01-15 12:35 EST – 2026-01-15 12:36 EST"
  end

  test "omits media previews when image inclusion is disabled", context do
    {:ok, preference} = Notifications.update_preference(context.preference, %{include_images: false})

    post =
      context.profile
      |> post_fixture(%{media_urls: ["https://example.com/post.jpg"]})
      |> Repo.preload(:tracked_profile)

    story =
      context.profile
      |> story_fixture(%{media_url: "https://example.com/story.jpg"})
      |> Repo.preload(:tracked_profile)

    email = build_email(%{context | preference: preference}, %{posts: [post], stories: [story]})

    refute email.html_body =~ ~s(alt="Instagram post preview")
    refute email.html_body =~ ~s(alt="Instagram story screenshot")
  end

  defp build_email(context, attrs) do
    DigestEmail.build(context.user, context.preference, %{
      posts: attrs.posts,
      stories: attrs.stories,
      period_start: context.period_start,
      period_end: context.period_end
    })
  end
end
