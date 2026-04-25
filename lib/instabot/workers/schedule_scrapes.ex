defmodule Instabot.Workers.ScheduleScrapes do
  @moduledoc """
  Cron-triggered worker that fans out ScrapeProfile jobs for all active tracked profiles.
  """

  use Oban.Worker, queue: :scraping, max_attempts: 1

  alias Instabot.Instagram
  alias Instabot.Scraping.Events
  alias Instabot.Workers.ScrapeProfile

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    profiles = Instagram.list_active_tracked_profiles()

    Logger.info("ScheduleScrapes: enqueueing #{length(profiles)} profile scrape jobs")

    Enum.each(profiles, fn profile ->
      case %{tracked_profile_id: profile.id} |> ScrapeProfile.new() |> Oban.insert() do
        {:ok, %{conflict?: true}} -> :ok
        {:ok, _job} -> Events.broadcast(profile, :queued)
        {:error, reason} -> Logger.warning("Failed to queue @#{profile.instagram_username}: #{inspect(reason)}")
      end
    end)

    :ok
  end
end
