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
    today = Date.utc_today()
    jobs = Notifications.due_profile_digest_jobs("weekly", today)

    Logger.info("SendWeeklyDigests: #{length(jobs)} profiles due for weekly digest on day #{Date.day_of_week(today)}")

    Enum.each(jobs, fn job ->
      %{user_id: job.user_id, digest_type: "weekly", tracked_profile_id: job.tracked_profile_id}
      |> SendDigest.new()
      |> Oban.insert()
    end)

    :ok
  end
end
