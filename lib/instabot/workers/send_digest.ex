defmodule Instabot.Workers.SendDigest do
  @moduledoc """
  Composes and sends a digest email for a single user covering a time period.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3,
    unique: [period: 3600, keys: [:user_id, :digest_type, :tracked_profile_id]]

  alias Instabot.Accounts
  alias Instabot.Instagram
  alias Instabot.Media
  alias Instabot.Notifications
  alias Instabot.Notifications.DigestEmail
  alias Instabot.Repo
  alias Instabot.Workers.ProcessOCR

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "digest_type" => digest_type} = args}) do
    user = Accounts.get_user!(user_id)
    tracked_profile_id = tracked_profile_id_from_args(args)
    preference = effective_preference(user_id, tracked_profile_id)
    period_start = determine_period_start(user_id, digest_type, tracked_profile_id)
    period_end = DateTime.utc_now(:second)
    tracked_profile_ids = tracked_profile_ids(tracked_profile_id)

    posts = Instagram.get_new_posts_since(user_id, period_start, tracked_profile_ids)
    stories = Instagram.get_new_stories_since(user_id, period_start, tracked_profile_ids)
    stories = process_pending_ocr(preference, stories)

    case {posts, stories} do
      {[], []} ->
        :ok

      _ ->
        send_digest(user, preference, digest_type, posts, stories, period_start, period_end, tracked_profile_id)
    end
  end

  defp send_digest(user, preference, digest_type, posts, stories, period_start, period_end, tracked_profile_id) do
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
        period_end: period_end,
        tracked_profile_id: tracked_profile_id
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

  defp determine_period_start(user_id, digest_type, nil) do
    case Notifications.last_digest_for_user(user_id, digest_type) do
      %{period_end: period_end} when not is_nil(period_end) ->
        period_end

      _ ->
        default_lookback(digest_type)
    end
  end

  defp determine_period_start(user_id, digest_type, tracked_profile_id) do
    case Notifications.last_digest_for_profile(user_id, digest_type, tracked_profile_id) do
      %{period_end: period_end} when not is_nil(period_end) ->
        period_end

      _ ->
        default_lookback(digest_type)
    end
  end

  defp effective_preference(user_id, nil), do: Notifications.get_or_create_preference(user_id)

  defp effective_preference(user_id, tracked_profile_id) do
    Notifications.effective_profile_preference(user_id, tracked_profile_id)
  end

  defp tracked_profile_id_from_args(%{"tracked_profile_id" => tracked_profile_id}), do: tracked_profile_id
  defp tracked_profile_id_from_args(_args), do: nil

  defp tracked_profile_ids(nil), do: []
  defp tracked_profile_ids(tracked_profile_id), do: [tracked_profile_id]

  defp default_lookback("daily"), do: DateTime.add(DateTime.utc_now(:second), -1, :day)
  defp default_lookback("weekly"), do: DateTime.add(DateTime.utc_now(:second), -7, :day)
  defp default_lookback(_), do: DateTime.add(DateTime.utc_now(:second), -1, :day)
end
