defmodule Instabot.Scraper.StoriesScraper do
  @moduledoc """
  Scrapes stories from an Instagram profile's stories page.
  Captures screenshots and extracts metadata for each story frame.
  """

  alias Instabot.Encryption
  alias Instabot.Instagram
  alias Instabot.Instagram.InstagramConnection
  alias Instabot.Instagram.TrackedProfile
  alias Instabot.Scraper.AntiDetection
  alias Instabot.Scraper.Browser
  alias Instabot.Scraper.Parser
  alias Instabot.Scraper.Session
  alias Instabot.Scraper.Supervisor, as: ScraperSupervisor

  require Logger

  @stories_url "https://www.instagram.com/stories"
  @frame_delay_min 1_000
  @frame_delay_max 3_000
  @max_frames 30

  @story_data_js """
  (() => {
    try {
      const items = window.__additionalData ?
        Object.values(window.__additionalData)
          .filter(d => d && d.data && d.data.reels_media)
          .flatMap(d => d.data.reels_media)
          .flatMap(r => r.items || []) : [];
      return items.map(item => ({
        id: item.id || item.pk,
        is_video: !!item.video_resources || item.is_video,
        video_url: item.video_resources ? item.video_resources[0].src : null,
        image_url: item.display_url || item.display_resources ?
          (item.display_resources ? item.display_resources[item.display_resources.length - 1].src : item.display_url) : null,
        taken_at: item.taken_at_timestamp,
        expiring_at: item.expiring_at_timestamp
      }));
    } catch(error) { return []; }
  })()
  """

  @doc """
  Scrapes stories for the given username using the provided cookies.
  Returns `{:ok, [story_map]}` or `{:error, reason}`.

  Each story_map contains: `:instagram_story_id`, `:story_type`, `:media_url`,
  `:posted_at`, `:expires_at`, `:screenshot_base64`.
  """
  @spec scrape(String.t(), map() | [map()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def scrape(username, session_data, opts \\ []) do
    max_frames = Keyword.get(opts, :max_frames, @max_frames)

    with {:ok, browser} <- ScraperSupervisor.start_browser() do
      result = scrape_with_browser(browser, username, session_data, max_frames)
      Browser.stop(browser)
      result
    end
  end

  @doc """
  Scrapes stories and persists them to the database for a tracked profile.
  Creates a scrape_log entry and saves screenshots to disk.
  Returns `{:ok, scrape_log}` or `{:error, reason}`.
  """
  @spec scrape_and_persist(TrackedProfile.t(), InstagramConnection.t(), keyword()) ::
          {:ok, Instagram.ScrapeLog.t()} | {:error, term()}
  def scrape_and_persist(%TrackedProfile{} = profile, %InstagramConnection{} = connection, opts \\ []) do
    case Instagram.create_scrape_log(profile.id, %{scrape_type: "stories"}) do
      {:ok, log} ->
        with {:ok, session_data} <- Encryption.decrypt_term(connection.encrypted_cookies),
             {:ok, stories} <- scrape(profile.instagram_username, session_data, opts) do
          persisted_count = persist_stories(profile, stories)
          Instagram.update_last_scraped(profile)
          Instagram.complete_scrape_log(log, %{stories_found: persisted_count})
        else
          {:error, reason} = error ->
            Instagram.fail_scrape_log(log, inspect(reason))
            error
        end

      {:error, _reason} = error ->
        error
    end
  end

  # --- Private ---

  defp scrape_with_browser(browser, username, session_data, max_frames) do
    with {:ok, _} <- Browser.launch(browser, AntiDetection.launch_options()),
         {:ok, page_id} <- Session.setup_session_from_data(browser, session_data),
         :ok <- navigate_to_stories(browser, page_id, username) do
      collect_story_frames(browser, page_id, max_frames)
    end
  end

  defp navigate_to_stories(browser, page_id, username) do
    url = "#{@stories_url}/#{username}/"
    AntiDetection.wait()

    with {:ok, _} <- Browser.navigate(browser, page_id, url, wait_until: "load"),
         {:ok, html} <- Browser.get_page_content(browser, page_id) do
      if Parser.login_page?(html) do
        {:error, :session_expired}
      else
        :ok
      end
    end
  end

  defp collect_story_frames(browser, page_id, max_frames) do
    with {:ok, js_data} <- Browser.evaluate(browser, page_id, @story_data_js),
         {:ok, json_responses} <- Browser.get_json_responses(browser, page_id) do
      story_metadata = story_metadata(js_data, json_responses)
      stories = capture_frames(browser, page_id, story_metadata, max_frames)
      {:ok, stories}
    end
  end

  defp story_metadata(js_data, json_responses) do
    case Parser.extract_stories_from_responses(json_responses) do
      [] -> Parser.extract_stories(js_data || [])
      stories -> stories
    end
  end

  defp capture_frames(browser, page_id, metadata, max_frames) do
    metadata
    |> Enum.take(max_frames)
    |> Enum.with_index()
    |> Enum.reduce([], fn {story_meta, index}, acc ->
      AntiDetection.wait(@frame_delay_min, @frame_delay_max)

      screenshot_result =
        if index > 0 do
          advance_and_screenshot(browser, page_id)
        else
          Browser.screenshot(browser, page_id)
        end

      case screenshot_result do
        {:ok, %{"base64" => base64}} ->
          story = Map.put(story_meta, :screenshot_base64, base64)
          [story | acc]

        {:error, reason} ->
          Logger.warning("Failed to capture story frame #{index}: #{inspect(reason)}")
          acc
      end
    end)
    |> Enum.reverse()
  end

  defp advance_and_screenshot(browser, page_id) do
    case Browser.click(browser, page_id, "button[aria-label='Next']") do
      {:ok, _} ->
        AntiDetection.wait(500, 1_000)
        Browser.screenshot(browser, page_id)

      {:error, _} ->
        Browser.screenshot(browser, page_id)
    end
  end

  defp persist_stories(profile, stories) do
    screenshot_dir = screenshot_dir_for_profile(profile)
    File.mkdir_p!(screenshot_dir)

    Enum.count(stories, fn story ->
      screenshot_path = save_screenshot(screenshot_dir, story)

      story_attrs = %{
        instagram_story_id: story.instagram_story_id,
        story_type: story.story_type,
        media_url: story.media_url,
        posted_at: story.posted_at,
        expires_at: story.expires_at,
        screenshot_path: screenshot_path
      }

      case Instagram.create_story(profile.id, story_attrs) do
        {:ok, _story} -> true
        {:error, _changeset} -> false
      end
    end)
  end

  defp save_screenshot(screenshot_dir, %{screenshot_base64: base64, instagram_story_id: story_id})
       when is_binary(base64) do
    filename = "#{story_id}.png"
    path = Path.join(screenshot_dir, filename)
    File.write!(path, Base.decode64!(base64))
    path
  end

  defp save_screenshot(_screenshot_dir, _story), do: nil

  defp screenshot_dir_for_profile(profile) do
    base_dir = scraper_config()[:screenshot_dir] || "priv/static/screenshots"
    Path.join(base_dir, profile.id)
  end

  defp scraper_config do
    Application.get_env(:instabot, Instabot.Scraper, [])
  end
end
