defmodule Instabot.Workers.SendWeeklyDigests do
  @moduledoc """
  Cron-triggered worker that finds users due for a weekly digest and fans out SendDigest jobs.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 1

  alias Instabot.Notifications
  alias Instabot.Workers.SendDigest

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.day_of_week(Date.utc_today())
    preferences = Notifications.list_preferences_by_frequency("weekly")

    matching =
      Enum.filter(preferences, fn pref ->
        pref.weekly_send_day == today
      end)

    Logger.info("SendWeeklyDigests: #{length(matching)} users due for weekly digest on day #{today}")

    Enum.each(matching, fn pref ->
      %{user_id: pref.user_id, digest_type: "weekly"}
      |> SendDigest.new()
      |> Oban.insert()
    end)

    :ok
  end
end
