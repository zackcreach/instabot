defmodule Instabot.Workers.ScrapeProfile do
  @moduledoc """
  Scrapes posts and stories for a single tracked profile.
  Enqueues downstream DownloadImage and ProcessOCR jobs on completion.
  """

  use Oban.Worker,
    queue: :scraping,
    max_attempts: 2,
    unique: [period: 300, keys: [:tracked_profile_id]]

  alias Instabot.Instagram
  alias Instabot.Notifications
  alias Instabot.Scraper.PostsScraper
  alias Instabot.Scraper.StoriesScraper
  alias Instabot.Workers.DownloadImage
  alias Instabot.Workers.ProcessOCR
  alias Instabot.Workers.SendImmediateNotification

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"tracked_profile_id" => tracked_profile_id}}) do
    profile = Instagram.get_tracked_profile!(tracked_profile_id)
    result = do_scrape(profile)
    broadcast_completion(profile)
    result
  end

  defp do_scrape(profile) do
    with :ok <- verify_active(profile),
         {:ok, connection} <- get_connection(profile.user_id) do
      scrape_posts(profile, connection)
      scrape_stories(profile, connection)
      enqueue_downstream_jobs(profile)
      maybe_enqueue_immediate_notification(profile.user_id)
      :ok
    end
  end

  defp verify_active(%{is_active: true}), do: :ok
  defp verify_active(_profile), do: {:cancel, "profile is inactive"}

  defp get_connection(user_id) do
    case Instagram.get_connection_for_user(user_id) do
      %{status: "connected"} = connection -> {:ok, connection}
      %{status: status} -> {:cancel, "connection status: #{status}"}
      nil -> {:cancel, "no instagram connection"}
    end
  end

  defp scrape_posts(profile, connection) do
    case PostsScraper.scrape_and_persist(profile, connection) do
      {:ok, log} ->
        Logger.info("Scraped #{log.posts_found} posts for @#{profile.instagram_username}")

      {:error, reason} ->
        Logger.warning("Post scrape failed for @#{profile.instagram_username}: #{inspect(reason)}")
    end
  end

  defp scrape_stories(profile, connection) do
    case StoriesScraper.scrape_and_persist(profile, connection) do
      {:ok, log} ->
        Logger.info("Scraped #{log.stories_found} stories for @#{profile.instagram_username}")

      {:error, reason} ->
        Logger.warning("Story scrape failed for @#{profile.instagram_username}: #{inspect(reason)}")
    end
  end

  defp enqueue_downstream_jobs(profile) do
    enqueue_image_downloads(profile.id)
    enqueue_ocr_jobs(profile.id)
  end

  defp enqueue_image_downloads(tracked_profile_id) do
    tracked_profile_id
    |> Instagram.get_posts_needing_images()
    |> Enum.each(fn post ->
      post.media_urls
      |> Enum.with_index()
      |> Enum.each(fn {url, position} ->
        %{post_id: post.id, url: url, position: position}
        |> DownloadImage.new()
        |> Oban.insert()
      end)
    end)
  end

  defp enqueue_ocr_jobs(tracked_profile_id) do
    tracked_profile_id
    |> Instagram.get_stories_pending_ocr()
    |> Enum.each(fn story ->
      %{story_id: story.id}
      |> ProcessOCR.new()
      |> Oban.insert()
    end)
  end

  defp maybe_enqueue_immediate_notification(user_id) do
    case Notifications.get_preference_for_user(user_id) do
      %{frequency: "immediate"} ->
        %{user_id: user_id}
        |> SendImmediateNotification.new()
        |> Oban.insert()

      _ ->
        :ok
    end
  end

  defp broadcast_completion(profile) do
    Phoenix.PubSub.broadcast(
      Instabot.PubSub,
      "scrape_updates:#{profile.user_id}",
      {:scrape_completed, profile.id}
    )
  end
end
