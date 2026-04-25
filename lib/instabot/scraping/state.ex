defmodule Instabot.Scraping.State do
  @moduledoc false

  import Ecto.Query

  alias Instabot.Instagram.ScrapeLog
  alias Instabot.Instagram.TrackedProfile
  alias Instabot.Repo
  alias Instabot.Scraping.Events

  @active_job_states ~w(available scheduled executing retryable)
  @terminal_job_states ~w(completed discarded cancelled)
  @tracked_job_states @active_job_states ++ @terminal_job_states
  @active_window_minutes 45

  def list_for_user(user_id) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -@active_window_minutes, :minute)

    TrackedProfile
    |> join(
      :inner,
      [profile],
      job in Oban.Job,
      on: fragment("?->>'tracked_profile_id'", job.args) == profile.id
    )
    |> where([profile, job], profile.user_id == ^user_id)
    |> where([_profile, job], job.worker == "Instabot.Workers.ScrapeProfile")
    |> where([_profile, job], job.state in ^@tracked_job_states)
    |> where(
      [_profile, job],
      job.inserted_at >= ^cutoff or job.scheduled_at >= ^cutoff or job.attempted_at >= ^cutoff
    )
    |> order_by([_profile, job], desc: job.inserted_at)
    |> select([profile, job], {profile, job.state})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {profile, job_state}, states ->
      Map.put_new(states, profile.id, event_for_job(profile, job_state))
    end)
  end

  defp event_for_job(profile, job_state) when job_state in ["available", "scheduled", "retryable"] do
    Events.build(profile, :queued)
  end

  defp event_for_job(profile, "executing") do
    case latest_started_log(profile.id) do
      %{scrape_type: "posts"} -> Events.build(profile, :scraping_posts)
      %{scrape_type: "stories"} -> Events.build(profile, :scraping_stories)
      nil -> Events.build(profile, :started)
    end
  end

  defp event_for_job(profile, "completed") do
    Events.build(profile, :completed)
  end

  defp event_for_job(profile, "discarded") do
    Events.build(profile, :failed)
  end

  defp event_for_job(profile, "cancelled") do
    Events.build(profile, :cancelled)
  end

  defp latest_started_log(profile_id) do
    ScrapeLog
    |> where(tracked_profile_id: ^profile_id, status: "started")
    |> order_by(desc: :started_at)
    |> limit(1)
    |> Repo.one()
  end
end
