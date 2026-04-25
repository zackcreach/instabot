defmodule Instabot.Notifications.DigestEmail do
  @moduledoc """
  Composes digest emails using Swoosh for new posts and stories.
  Sends both plain-text and HTML bodies.
  """

  import Swoosh.Email

  alias Instabot.Accounts.User
  alias Instabot.Notifications.NotificationPreference

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
          (preference.include_ocr and story.ocr_text not in [nil, ""]) &&
            "  OCR: #{String.slice(story.ocr_text, 0, 300)}"
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
        image_line =
          if preference.include_images and post.media_urls != [] do
            "<p style=\"margin:4px 0 0;color:#71717a;font-size:13px;\">#{length(post.media_urls)} #{pluralize(length(post.media_urls), "image", "images")}</p>"
          else
            ""
          end

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
          #{caption_line}
          #{permalink_line}
          #{image_line}
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
        ocr_line =
          if preference.include_ocr and story.ocr_text not in [nil, ""] do
            excerpt = story.ocr_text |> String.slice(0, 300) |> html_escape()

            "<p style=\"margin:6px 0 0;color:#3f3f46;font-size:13px;line-height:1.5;font-style:italic;\">\"#{excerpt}\"</p>"
          else
            ""
          end

        """
        <div style="margin-bottom:20px;padding-bottom:20px;border-bottom:1px solid #f4f4f5;">
          <p style="margin:0;font-size:14px;font-weight:600;color:#18181b;">
            @#{html_escape(story.tracked_profile.instagram_username)}
            <span style="font-weight:400;color:#a1a1aa;margin-left:6px;">#{html_escape(story.story_type)}</span>
          </p>
          #{ocr_line}
        </div>
        """
      end)

    header <> Enum.join(items)
  end

  defp html_escape(nil), do: ""
  defp html_escape(str), do: str |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  defp format_datetime(_), do: "N/A"
end
