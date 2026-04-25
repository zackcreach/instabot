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

    case {posts, stories} do
      {[], []} ->
        :ok

      _ ->
        email =
          DigestEmail.build(user, preference, %{
            posts: posts,
            stories: stories,
            period_start: period_start,
            period_end: period_end
          })

        with {:ok, _metadata} <- Instabot.Mailer.deliver(email) do
          Notifications.create_email_digest(user_id, %{
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
  end

  defp determine_period_start(user_id) do
    case Notifications.last_digest_for_user(user_id, "immediate") do
      %{period_end: period_end} when not is_nil(period_end) -> period_end
      _ -> DateTime.add(DateTime.utc_now(:second), -1, :day)
    end
  end
end
