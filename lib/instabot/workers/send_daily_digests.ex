defmodule Instabot.Workers.SendDailyDigests do
  @moduledoc """
  Cron-triggered worker that finds users due for a daily digest and fans out SendDigest jobs.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 1

  alias Instabot.Notifications
  alias Instabot.Workers.SendDigest

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    current_hour = Time.utc_now().hour
    preferences = Notifications.list_preferences_by_frequency("daily")

    matching =
      Enum.filter(preferences, fn pref ->
        pref.daily_send_at != nil and pref.daily_send_at.hour == current_hour
      end)

    Logger.info("SendDailyDigests: #{length(matching)} users due for daily digest at hour #{current_hour}")

    Enum.each(matching, fn pref ->
      %{user_id: pref.user_id, digest_type: "daily"}
      |> SendDigest.new()
      |> Oban.insert()
    end)

    :ok
  end
end
