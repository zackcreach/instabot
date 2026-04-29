defmodule Instabot.Workers.SendDigest do
  @moduledoc """
  Composes and sends a digest email for a single user covering a time period.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3,
    unique: [period: 3600, keys: [:user_id, :digest_type]]

  alias Instabot.Accounts
  alias Instabot.Instagram
  alias Instabot.Media
  alias Instabot.Notifications
  alias Instabot.Notifications.DigestEmail
  alias Instabot.Repo
  alias Instabot.Workers.ProcessOCR

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "digest_type" => digest_type}}) do
    user = Accounts.get_user!(user_id)
    preference = Notifications.get_or_create_preference(user_id)
    period_start = determine_period_start(user_id, digest_type)
    period_end = DateTime.utc_now(:second)

    posts = Instagram.get_new_posts_since(user_id, period_start)
    stories = Instagram.get_new_stories_since(user_id, period_start)
    stories = process_pending_ocr(preference, stories)

    case {posts, stories} do
      {[], []} ->
        :ok

      _ ->
        send_digest(user, preference, digest_type, posts, stories, period_start, period_end)
    end
  end

  defp send_digest(user, preference, digest_type, posts, stories, period_start, period_end) do
    email =
      DigestEmail.build(user, preference, %{
        posts: posts,
        stories: stories,
        period_start: period_start,
        period_end: period_end
      })

    with {:ok, _metadata} <- Instabot.Mailer.deliver(email) do
      Notifications.create_email_digest(user.id, %{
        digest_type: digest_type,
        posts_count: length(posts),
        stories_count: length(stories),
        sent_at: period_end,
        period_start: period_start,
        period_end: period_end
      })

      :ok
    end
  end

  defp process_pending_ocr(%{include_ocr: true}, stories) do
    Enum.map(stories, fn story ->
      if story_waiting_for_ocr?(story) do
        ProcessOCR.perform(%Oban.Job{args: %{"story_id" => story.id}})

        story.id
        |> Instagram.get_story!()
        |> Repo.preload(:tracked_profile)
      else
        story
      end
    end)
  end

  defp process_pending_ocr(_preference, stories), do: stories

  defp story_waiting_for_ocr?(%{ocr_text: text}) when is_binary(text) and text != "", do: false

  defp story_waiting_for_ocr?(%{ocr_status: status} = story) when status in ["pending", "failed"] do
    Media.story_has_screenshot?(story)
  end

  defp story_waiting_for_ocr?(_story), do: false

  defp determine_period_start(user_id, digest_type) do
    case Notifications.last_digest_for_user(user_id, digest_type) do
      %{period_end: period_end} when not is_nil(period_end) ->
        period_end

      _ ->
        default_lookback(digest_type)
    end
  end

  defp default_lookback("daily"), do: DateTime.add(DateTime.utc_now(:second), -1, :day)
  defp default_lookback("weekly"), do: DateTime.add(DateTime.utc_now(:second), -7, :day)
  defp default_lookback(_), do: DateTime.add(DateTime.utc_now(:second), -1, :day)
end
