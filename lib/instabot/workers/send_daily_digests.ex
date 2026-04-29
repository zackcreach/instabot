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
    current_time = Time.utc_now()
    jobs = Notifications.due_profile_digest_jobs("daily", current_time)

    Logger.info("SendDailyDigests: #{length(jobs)} profiles due for daily digest at hour #{current_time.hour}")

    Enum.each(jobs, fn job ->
      %{user_id: job.user_id, digest_type: "daily", tracked_profile_id: job.tracked_profile_id}
      |> SendDigest.new()
      |> Oban.insert()
    end)

    :ok
  end
end
