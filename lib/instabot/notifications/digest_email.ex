defmodule Instabot.Notifications.DigestEmail do
  @moduledoc """
  Composes digest emails using Swoosh for new posts and stories.
  Sends both plain-text and HTML bodies.
  """

  import Swoosh.Email

  alias Instabot.Accounts.User
  alias Instabot.Media
  alias Instabot.Notifications.NotificationPreference

  @eastern_time_zone "America/New_York"

  @spec build(User.t(), NotificationPreference.t(), map()) :: Swoosh.Email.t()
  def build(user, preference, %{posts: posts, stories: stories, period_start: period_start, period_end: period_end}) do
    recipient = preference.email_address || user.email
    post_count = length(posts)
    story_count = length(stories)
    subject_line = build_subject(post_count, story_count)
    unsubscribe_url = build_unsubscribe_url(user.id)
    from_email = Application.get_env(:instabot, :from_email, "noreply@example.com")

    period = %{start: period_start, end: period_end}

    new()
    |> to(recipient)
    |> from({"Instabot", from_email})
    |> subject(subject_line)
    |> text_body(build_text(posts, stories, preference, period, unsubscribe_url))
    |> html_body(build_html(posts, stories, preference, period, unsubscribe_url))
  end

  def unsubscribe_token(user_id) do
    Phoenix.Token.sign(InstabotWeb.Endpoint, "unsubscribe", user_id)
  end

  defp build_unsubscribe_url(user_id) do
    token = unsubscribe_token(user_id)
    InstabotWeb.Endpoint.url() <> "/unsubscribe/#{token}"
  end

  defp build_subject(0, story_count), do: "Instabot: #{story_count} new #{pluralize(story_count, "story", "stories")}"
  defp build_subject(post_count, 0), do: "Instabot: #{post_count} new #{pluralize(post_count, "post", "posts")}"

  defp build_subject(post_count, story_count),
    do:
      "Instabot: #{post_count} new #{pluralize(post_count, "post", "posts")} and #{story_count} new #{pluralize(story_count, "story", "stories")}"

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_, _singular, plural), do: plural

  defp build_text(posts, stories, preference, period, unsubscribe_url) do
    sections = [
      "Instabot Digest",
      "Period: #{format_datetime(period.start)} – #{format_datetime(period.end)}",
      "",
      text_posts_section(posts, preference),
      text_stories_section(stories, preference),
      "",
      "─────────────────────────────────",
      "To stop receiving these emails, visit:",
      unsubscribe_url
    ]

    sections
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp text_posts_section([], _preference), do: nil

  defp text_posts_section(posts, preference) do
    header = "--- #{length(posts)} New Posts ---\n"

    items =
      Enum.map(posts, fn post ->
        lines = [
          "@#{post.tracked_profile.instagram_username} · #{post.post_type}",
          post.caption && "  #{String.slice(post.caption, 0, 200)}",
          post.permalink && "  #{post.permalink}",
          (preference.include_images and post.media_urls != []) &&
            "  Images: #{length(post.media_urls)}"
        ]

        lines |> Enum.filter(& &1) |> Enum.join("\n")
      end)

    [header | items]
  end

  defp text_stories_section([], _preference), do: nil

  defp text_stories_section(stories, preference) do
    header = "\n--- #{length(stories)} New Stories ---\n"

    items =
      Enum.map(stories, fn story ->
        lines = [
          "@#{story.tracked_profile.instagram_username} · #{story.story_type}",
          text_story_ocr_line(story, preference)
        ]

        lines |> Enum.filter(& &1) |> Enum.join("\n")
      end)

    [header | items]
  end

  defp build_html(posts, stories, preference, period, unsubscribe_url) do
    posts_html = html_posts_section(posts, preference)
    stories_html = html_stories_section(stories, preference)

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>Instabot Digest</title>
    </head>
    <body style="margin:0;padding:0;background:#f4f4f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;">
      <table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f5;padding:32px 0;">
        <tr>
          <td align="center">
            <table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;">

              <!-- Header -->
              <tr>
                <td style="background:#18181b;border-radius:12px 12px 0 0;padding:28px 32px;">
                  <span style="color:#ffffff;font-size:22px;font-weight:700;letter-spacing:-0.5px;">Instabot</span>
                  <span style="color:#a1a1aa;font-size:14px;margin-left:12px;">Digest</span>
                </td>
              </tr>

              <!-- Period -->
              <tr>
                <td style="background:#ffffff;padding:20px 32px 0;border-left:1px solid #e4e4e7;border-right:1px solid #e4e4e7;">
                  <p style="margin:0;color:#71717a;font-size:13px;">
                    #{format_datetime(period.start)} – #{format_datetime(period.end)}
                  </p>
                </td>
              </tr>

              <!-- Body -->
              <tr>
                <td style="background:#ffffff;padding:20px 32px 28px;border-left:1px solid #e4e4e7;border-right:1px solid #e4e4e7;border-bottom:1px solid #e4e4e7;border-radius:0 0 12px 12px;">
                  #{posts_html}
                  #{stories_html}
                </td>
              </tr>

              <!-- Footer -->
              <tr>
                <td style="padding:20px 32px;text-align:center;">
                  <p style="margin:0;color:#a1a1aa;font-size:12px;">
                    You're receiving this because you enabled Instabot digest emails.<br />
                    <a href="#{unsubscribe_url}" style="color:#71717a;text-decoration:underline;">Unsubscribe</a>
                  </p>
                </td>
              </tr>

            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  defp html_posts_section([], _preference), do: ""

  defp html_posts_section(posts, preference) do
    header = """
    <h2 style="margin:0 0 16px;font-size:16px;font-weight:600;color:#18181b;border-bottom:1px solid #f4f4f5;padding-bottom:12px;">
      #{length(posts)} New #{pluralize(length(posts), "Post", "Posts")}
    </h2>
    """

    items =
      Enum.map(posts, fn post ->
        media_urls = post_media_urls(post)
        image_grid = html_media_grid(media_urls, preference)

        caption_line =
          if post.caption && post.caption != "" do
            excerpt = post.caption |> String.slice(0, 200) |> html_escape()
            "<p style=\"margin:6px 0 0;color:#3f3f46;font-size:14px;line-height:1.5;\">#{excerpt}</p>"
          else
            ""
          end

        permalink_line =
          if post.permalink do
            "<p style=\"margin:6px 0 0;\"><a href=\"#{post.permalink}\" style=\"color:#6366f1;font-size:13px;text-decoration:none;\">View on Instagram →</a></p>"
          else
            ""
          end

        """
        <div style="margin-bottom:20px;padding-bottom:20px;border-bottom:1px solid #f4f4f5;">
          <p style="margin:0;font-size:14px;font-weight:600;color:#18181b;">
            @#{html_escape(post.tracked_profile.instagram_username)}
            <span style="font-weight:400;color:#a1a1aa;margin-left:6px;">#{html_escape(post.post_type)}</span>
          </p>
          #{image_grid}
          #{caption_line}
          #{permalink_line}
        </div>
        """
      end)

    header <> Enum.join(items)
  end

  defp html_stories_section([], _preference), do: ""

  defp html_stories_section(stories, preference) do
    spacer = "<div style=\"height:8px;\"></div>"

    header = """
    #{spacer}
    <h2 style="margin:16px 0 16px;font-size:16px;font-weight:600;color:#18181b;border-bottom:1px solid #f4f4f5;padding-bottom:12px;">
      #{length(stories)} New #{pluralize(length(stories), "Story", "Stories")}
    </h2>
    """

    items =
      Enum.map(stories, fn story ->
        preview_url = story_preview_url(story)
        preview = html_story_preview(preview_url, preference)

        ocr_line = html_story_ocr_line(story, preference)

        """
        <div style="margin-bottom:20px;padding-bottom:20px;border-bottom:1px solid #f4f4f5;">
          <p style="margin:0;font-size:14px;font-weight:600;color:#18181b;">
            @#{html_escape(story.tracked_profile.instagram_username)}
            <span style="font-weight:400;color:#a1a1aa;margin-left:6px;">#{html_escape(story.story_type)}</span>
          </p>
          #{preview}
          #{ocr_line}
        </div>
        """
      end)

    header <> Enum.join(items)
  end

  defp html_escape(nil), do: ""
  defp html_escape(str), do: str |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp text_story_ocr_line(_story, %{include_ocr: false}), do: nil

  defp text_story_ocr_line(%{ocr_text: text}, _preference) when is_binary(text) and text != "" do
    "  OCR: #{String.slice(text, 0, 300)}"
  end

  defp text_story_ocr_line(%{ocr_status: "pending"}, _preference), do: "  OCR: pending"
  defp text_story_ocr_line(%{ocr_status: "processing"}, _preference), do: "  OCR: processing"
  defp text_story_ocr_line(%{ocr_status: "failed"}, _preference), do: "  OCR: failed"
  defp text_story_ocr_line(%{ocr_status: "completed"}, _preference), do: "  OCR: no text detected"
  defp text_story_ocr_line(_story, _preference), do: "  OCR: not available"

  defp html_story_ocr_line(_story, %{include_ocr: false}), do: ""

  defp html_story_ocr_line(%{ocr_text: text}, _preference) when is_binary(text) and text != "" do
    excerpt = text |> String.slice(0, 300) |> html_escape()

    "<p style=\"margin:8px 0 0;color:#3f3f46;font-size:13px;line-height:1.5;font-style:italic;\">\"#{excerpt}\"</p>"
  end

  defp html_story_ocr_line(story, _preference) do
    label =
      story
      |> ocr_status_label()
      |> html_escape()

    "<p style=\"margin:8px 0 0;color:#71717a;font-size:12px;line-height:1.4;\">OCR: #{label}</p>"
  end

  defp ocr_status_label(%{ocr_status: "pending"}), do: "pending"
  defp ocr_status_label(%{ocr_status: "processing"}), do: "processing"
  defp ocr_status_label(%{ocr_status: "failed"}), do: "failed"
  defp ocr_status_label(%{ocr_status: "completed"}), do: "no text detected"
  defp ocr_status_label(_story), do: "not available"

  defp html_media_grid(_media_urls, %{include_images: false}), do: ""
  defp html_media_grid([], _preference), do: ""

  defp html_media_grid(media_urls, _preference) do
    cells =
      media_urls
      |> Enum.take(3)
      |> Enum.map_join(fn url ->
        """
        <td width="33.333%" style="padding:0 6px 0 0;vertical-align:top;">
          <img src="#{html_escape(url)}" alt="Instagram post preview" width="172" style="display:block;width:100%;max-width:172px;height:172px;object-fit:cover;border-radius:8px;background:#f4f4f5;" />
        </td>
        """
      end)

    count_label =
      case length(media_urls) do
        count when count > 3 ->
          "<p style=\"margin:8px 0 0;color:#71717a;font-size:12px;\">+#{count - 3} more #{pluralize(count - 3, "image", "images")}</p>"

        _ ->
          ""
      end

    """
    <table width="100%" cellpadding="0" cellspacing="0" style="margin:12px 0 0;">
      <tr>
        #{cells}
      </tr>
    </table>
    #{count_label}
    """
  end

  defp html_story_preview(_preview_url, %{include_images: false}), do: ""
  defp html_story_preview(nil, _preference), do: ""

  defp html_story_preview(preview_url, _preference) do
    """
    <div style="margin:12px 0 0;">
      <img src="#{html_escape(preview_url)}" alt="Instagram story screenshot" width="180" style="display:block;width:180px;max-width:100%;height:320px;object-fit:cover;border-radius:8px;background:#f4f4f5;" />
    </div>
    """
  end

  defp post_media_urls(%{post_images: post_images}) when is_list(post_images) and post_images != [] do
    post_images
    |> Enum.sort_by(& &1.position)
    |> Enum.map(&post_image_url/1)
    |> Enum.reject(&is_nil/1)
  end

  defp post_media_urls(%{media_urls: media_urls}) when is_list(media_urls) do
    media_urls
    |> Enum.map(&absolute_media_url/1)
    |> Enum.reject(&is_nil/1)
  end

  defp post_media_urls(_post), do: []

  defp story_preview_url(%{screenshot_url: screenshot_url}) when is_binary(screenshot_url) and screenshot_url != "" do
    absolute_media_url(screenshot_url)
  end

  defp story_preview_url(%{screenshot_path: screenshot_path}) when is_binary(screenshot_path) and screenshot_path != "" do
    absolute_media_url(screenshot_path)
  end

  defp story_preview_url(%{media_url: media_url}) when is_binary(media_url) and media_url != "" do
    absolute_media_url(media_url)
  end

  defp story_preview_url(_story), do: nil

  defp post_image_url(%{cloudinary_secure_url: url}) when is_binary(url) and url != "", do: absolute_media_url(url)
  defp post_image_url(%{local_path: path}) when is_binary(path) and path != "", do: absolute_media_url(path)
  defp post_image_url(_post_image), do: nil

  defp absolute_media_url(nil), do: nil
  defp absolute_media_url(""), do: nil

  defp absolute_media_url(url) do
    url
    |> Media.to_url()
    |> absolute_url()
  end

  defp absolute_url("/" <> _ = path), do: InstabotWeb.Endpoint.url() <> path
  defp absolute_url(url), do: url

  defp format_datetime(%DateTime{} = datetime) do
    datetime
    |> eastern_datetime()
    |> Calendar.strftime("%Y-%m-%d %H:%M %Z")
  end

  defp format_datetime(_), do: "N/A"

  defp eastern_datetime(datetime) do
    case DateTime.shift_zone(datetime, @eastern_time_zone) do
      {:ok, eastern_datetime} -> eastern_datetime
      {:error, _reason} -> datetime
    end
  end
end
