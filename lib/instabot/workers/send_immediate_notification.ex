defmodule Instabot.Workers.SendImmediateNotification do
  @moduledoc """
  Sends an immediate notification email after a scrape completes,
  if the user has immediate frequency enabled. 5-minute uniqueness
  window consolidates burst scrapes into a single email.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3,
    unique: [period: 300, keys: [:user_id]]

  alias Instabot.Accounts
  alias Instabot.Instagram
  alias Instabot.Notifications
  alias Instabot.Notifications.DigestEmail

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    preference = Notifications.get_preference_for_user(user_id)

    case preference do
      %{frequency: "immediate"} ->
        send_immediate(user_id, preference)

      _ ->
        :ok
    end
  end

  defp send_immediate(user_id, preference) do
    user = Accounts.get_user!(user_id)
    period_start = determine_period_start(user_id)
    period_end = DateTime.utc_now(:second)

    posts = Instagram.get_new_posts_since(user_id, period_start)
    stories = Instagram.get_new_stories_since(user_id, period_start)

    cond do
      wait_for_ocr?(preference, stories) ->
        :ok

      {posts, stories} == {[], []} ->
        :ok

      true ->
        send_digest(user, preference, posts, stories, period_start, period_end)
    end
  end

  defp send_digest(user, preference, posts, stories, period_start, period_end) do
    email =
      DigestEmail.build(user, preference, %{
        posts: posts,
        stories: stories,
        period_start: period_start,
        period_end: period_end
      })

    with {:ok, _metadata} <- Instabot.Mailer.deliver(email) do
      Notifications.create_email_digest(user.id, %{
        digest_type: "immediate",
        posts_count: length(posts),
        stories_count: length(stories),
        sent_at: period_end,
        period_start: period_start,
        period_end: period_end
      })

      :ok
    end
  end

  defp wait_for_ocr?(%{include_ocr: true}, stories) do
    Enum.any?(stories, &story_waiting_for_ocr?/1)
  end

  defp wait_for_ocr?(_preference, _stories), do: false

  defp story_waiting_for_ocr?(%{ocr_text: text}) when is_binary(text) and text != "", do: false

  defp story_waiting_for_ocr?(%{ocr_status: status} = story) when status in ["pending", "processing"] do
    story_has_screenshot?(story)
  end

  defp story_waiting_for_ocr?(_story), do: false

  defp story_has_screenshot?(%{screenshot_url: screenshot_url}) when is_binary(screenshot_url) and screenshot_url != "" do
    true
  end

  defp story_has_screenshot?(%{screenshot_path: screenshot_path})
       when is_binary(screenshot_path) and screenshot_path != "" do
    true
  end

  defp story_has_screenshot?(_story), do: false

  defp determine_period_start(user_id) do
    case Notifications.last_digest_for_user(user_id, "immediate") do
      %{period_end: period_end} when not is_nil(period_end) -> period_end
      _ -> DateTime.add(DateTime.utc_now(:second), -1, :day)
    end
  end
end
