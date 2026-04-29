defmodule Instabot.Workers.SendImmediateNotification do
  @moduledoc """
  Sends an immediate notification email after a scrape completes,
  if the user has immediate frequency enabled. 5-minute uniqueness
  window consolidates burst scrapes into a single email.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3,
    unique: [period: 300, keys: [:user_id, :tracked_profile_id]]

  alias Instabot.Accounts
  alias Instabot.Instagram
  alias Instabot.Media
  alias Instabot.Notifications
  alias Instabot.Notifications.DigestEmail

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id} = args}) do
    tracked_profile_id = tracked_profile_id_from_args(args)
    preference = effective_preference(user_id, tracked_profile_id)

    case preference do
      %{frequency: "immediate"} ->
        send_immediate(user_id, preference, tracked_profile_id)

      _ ->
        :ok
    end
  end

  defp send_immediate(user_id, preference, tracked_profile_id) do
    user = Accounts.get_user!(user_id)
    period_start = determine_period_start(user_id, tracked_profile_id)
    period_end = DateTime.utc_now(:second)
    tracked_profile_ids = tracked_profile_ids(tracked_profile_id)

    posts = Instagram.get_new_posts_since(user_id, period_start, tracked_profile_ids)
    stories = Instagram.get_new_stories_since(user_id, period_start, tracked_profile_ids)

    cond do
      wait_for_ocr?(preference, stories) ->
        :ok

      {posts, stories} == {[], []} ->
        :ok

      true ->
        send_digest(user, preference, posts, stories, period_start, period_end, tracked_profile_id)
    end
  end

  defp send_digest(user, preference, posts, stories, period_start, period_end, tracked_profile_id) do
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
        period_end: period_end,
        tracked_profile_id: tracked_profile_id
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
    Media.story_has_screenshot?(story)
  end

  defp story_waiting_for_ocr?(_story), do: false

  defp determine_period_start(user_id, nil) do
    case Notifications.last_digest_for_user(user_id, "immediate") do
      %{period_end: period_end} when not is_nil(period_end) -> period_end
      _ -> DateTime.add(DateTime.utc_now(:second), -1, :day)
    end
  end

  defp determine_period_start(user_id, tracked_profile_id) do
    case Notifications.last_digest_for_profile(user_id, "immediate", tracked_profile_id) do
      %{period_end: period_end} when not is_nil(period_end) -> period_end
      _ -> DateTime.add(DateTime.utc_now(:second), -1, :day)
    end
  end

  defp effective_preference(user_id, nil), do: Notifications.get_preference_for_user(user_id)

  defp effective_preference(user_id, tracked_profile_id) do
    Notifications.effective_profile_preference(user_id, tracked_profile_id)
  end

  defp tracked_profile_id_from_args(%{"tracked_profile_id" => tracked_profile_id}), do: tracked_profile_id
  defp tracked_profile_id_from_args(_args), do: nil

  defp tracked_profile_ids(nil), do: []
  defp tracked_profile_ids(tracked_profile_id), do: [tracked_profile_id]
end
