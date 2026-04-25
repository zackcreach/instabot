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
  alias Instabot.Scraping.Events
  alias Instabot.Workers.DownloadImage
  alias Instabot.Workers.ProcessOCR
  alias Instabot.Workers.SendImmediateNotification

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"tracked_profile_id" => tracked_profile_id}}) do
    profile = Instagram.get_tracked_profile!(tracked_profile_id)

    try do
      Events.broadcast(profile, :started)
      result = do_scrape(profile)
      broadcast_result(profile, result)
      result
    catch
      kind, reason ->
        error = Exception.format(kind, reason, __STACKTRACE__)
        Events.broadcast(profile, :failed, %{error: error, message: "Scrape failed"})
        {:error, {kind, reason}}
    end
  end

  defp do_scrape(profile) do
    with :ok <- verify_active(profile),
         {:ok, connection} <- get_connection(profile.user_id) do
      posts_result = scrape_posts(profile, connection)
      stories_result = scrape_stories(profile, connection)

      case scrape_result([posts_result, stories_result]) do
        :ok ->
          Events.broadcast(profile, :downstream)
          pending_ocr_count = enqueue_downstream_jobs(profile)
          maybe_enqueue_immediate_notification(profile.user_id, pending_ocr_count)
          :ok

        {:error, _reason} = error ->
          error
      end
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
    Events.broadcast(profile, :scraping_posts)

    case PostsScraper.scrape_and_persist(profile, connection) do
      {:ok, log} ->
        Logger.info("Scraped #{log.posts_found} posts for @#{profile.instagram_username}")
        {:ok, log}

      {:error, reason} ->
        Logger.warning("Post scrape failed for @#{profile.instagram_username}: #{inspect(reason)}")
        {:error, {:posts, reason}}
    end
  end

  defp scrape_stories(profile, connection) do
    Events.broadcast(profile, :scraping_stories)

    case StoriesScraper.scrape_and_persist(profile, connection) do
      {:ok, log} ->
        Logger.info("Scraped #{log.stories_found} stories for @#{profile.instagram_username}")
        {:ok, log}

      {:error, reason} ->
        Logger.warning("Story scrape failed for @#{profile.instagram_username}: #{inspect(reason)}")
        {:error, {:stories, reason}}
    end
  end

  defp scrape_result(results) do
    if Enum.any?(results, fn result -> match?({:ok, _log}, result) end) do
      :ok
    else
      {:error, Enum.map(results, fn {:error, reason} -> reason end)}
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
    stories = Instagram.get_stories_pending_ocr(tracked_profile_id)

    Enum.each(stories, fn story ->
      %{story_id: story.id}
      |> ProcessOCR.new()
      |> Oban.insert()
    end)

    length(stories)
  end

  defp maybe_enqueue_immediate_notification(user_id, pending_ocr_count) do
    case Notifications.get_preference_for_user(user_id) do
      %{frequency: "immediate", include_ocr: true} when pending_ocr_count > 0 ->
        :ok

      %{frequency: "immediate"} ->
        %{user_id: user_id}
        |> SendImmediateNotification.new()
        |> Oban.insert()

      _ ->
        :ok
    end
  end

  defp broadcast_result(profile, :ok), do: Events.broadcast(profile, :completed)

  defp broadcast_result(profile, {:cancel, reason}) do
    Events.broadcast(profile, :cancelled, %{error: reason, message: "Scrape cancelled: #{reason}"})
  end

  defp broadcast_result(profile, {:error, reason}) do
    Events.broadcast(profile, :failed, %{error: inspect(reason), message: "Scrape failed"})
  end
end
