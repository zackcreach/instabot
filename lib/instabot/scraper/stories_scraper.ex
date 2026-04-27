defmodule Instabot.Scraper.StoriesScraper do
  @moduledoc """
  Scrapes stories from an Instagram profile's stories page.
  Captures screenshots and extracts metadata for each story frame.
  """

  alias Instabot.Encryption
  alias Instabot.Instagram
  alias Instabot.Instagram.Events
  alias Instabot.Instagram.InstagramConnection
  alias Instabot.Instagram.TrackedProfile
  alias Instabot.Media
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

  @dismiss_story_gate_js """
  (() => {
    const elements = Array.from(document.querySelectorAll("button, div[role='button']"));
    const button = elements.find(element => /view story/i.test(element.innerText || element.textContent || ""));
    if (!button) return false;
    button.click();
    return true;
  })()
  """

  @story_viewer_state_js """
  (() => {
    const text = document.body ? document.body.innerText || "" : "";
    const hasViewStoryGate = /view story/i.test(text) && /will be able to see that you viewed/i.test(text);
    const hasStoryPath = window.location.pathname.startsWith("/stories/");
    const hasVisibleMedia = Array.from(document.querySelectorAll("video, img")).some(element => {
      const rect = element.getBoundingClientRect();
      return rect.width >= 200 && rect.height >= 200 && rect.top < window.innerHeight && rect.bottom > 0;
    });
    const hasViewerControls = Boolean(
      document.querySelector("button[aria-label='Next'], button[aria-label='Pause'], svg[aria-label='Pause'], svg[aria-label='Play']")
    );

    return { hasStoryPath, hasViewStoryGate, hasVisibleMedia, hasViewerControls };
  })()
  """

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
      try do
        scrape_with_browser(browser, username, session_data, max_frames)
      after
        Browser.stop(browser)
      end
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
        scrape_and_persist_with_log(profile, connection, log, opts)

      {:error, _reason} = error ->
        error
    end
  end

  # --- Private ---

  defp scrape_and_persist_with_log(profile, connection, log, opts) do
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
  catch
    kind, reason ->
      error_message = Exception.format(kind, reason, __STACKTRACE__)
      Instagram.fail_scrape_log(log, error_message)
      {:error, {kind, reason}}
  end

  defp scrape_with_browser(browser, username, session_data, max_frames) do
    with {:ok, _} <- Browser.launch(browser, AntiDetection.launch_options()),
         {:ok, page_id} <- Session.setup_session_from_data(browser, session_data),
         :ok <- navigate_to_stories(browser, page_id, username),
         :ok <- dismiss_story_gate(browser, page_id) do
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
    |> Enum.reduce_while([], fn {story_meta, index}, acc ->
      AntiDetection.wait(@frame_delay_min, @frame_delay_max)

      with :ok <- maybe_advance_story(browser, page_id, index),
           :ok <- dismiss_story_gate(browser, page_id),
           true <- story_viewer_ready?(browser, page_id),
           {:ok, %{"base64" => base64}} <- Browser.screenshot(browser, page_id) do
        story = Map.put(story_meta, :screenshot_base64, base64)
        {:cont, [story | acc]}
      else
        :done ->
          {:halt, acc}

        false ->
          Logger.warning("Skipping story frame #{index}: story viewer was not visible")
          {:halt, acc}

        {:error, reason} ->
          Logger.warning("Failed to capture story frame #{index}: #{inspect(reason)}")
          {:cont, acc}
      end
    end)
    |> Enum.reverse()
  end

  defp maybe_advance_story(_browser, _page_id, 0), do: :ok

  defp maybe_advance_story(browser, page_id, _index) do
    case Browser.click(browser, page_id, "button[aria-label='Next']") do
      {:ok, _} ->
        AntiDetection.wait(500, 1_000)
        :ok

      {:error, _} ->
        :done
    end
  end

  defp dismiss_story_gate(browser, page_id) do
    case Browser.evaluate(browser, page_id, @dismiss_story_gate_js) do
      {:ok, true} ->
        AntiDetection.wait(1_000, 2_000)
        :ok

      {:ok, _} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp story_viewer_ready?(browser, page_id) do
    case Browser.evaluate(browser, page_id, @story_viewer_state_js) do
      {:ok, %{"hasStoryPath" => true, "hasViewStoryGate" => false, "hasVisibleMedia" => true}} -> true
      {:ok, %{"hasStoryPath" => true, "hasViewStoryGate" => false, "hasViewerControls" => true}} -> true
      _ -> false
    end
  end

  defp persist_stories(profile, stories) do
    Enum.count(stories, fn story ->
      screenshot_attrs = upload_screenshot(profile, story)

      story_attrs =
        Map.merge(
          %{
            instagram_story_id: story.instagram_story_id,
            story_type: story.story_type,
            media_url: story.media_url,
            posted_at: story.posted_at,
            expires_at: story.expires_at
          },
          screenshot_attrs
        )

      case Instagram.upsert_story_from_scrape(profile.id, story_attrs) do
        {:ok, story, status} when status in [:inserted, :updated] ->
          Events.broadcast_story_created(profile, story)
          true

        {:ok, _story, :unchanged} ->
          false

        {:error, _changeset} ->
          false
      end
    end)
  end

  defp upload_screenshot(profile, %{screenshot_base64: base64, instagram_story_id: story_id}) when is_binary(base64) do
    subdirectory = Path.join("stories", profile.id)
    filename = "#{story_id}.png"

    case Media.upload_image(Base.decode64!(base64), subdirectory, filename, content_type: "image/png") do
      {:ok, result} ->
        %{
          screenshot_path: result[:local_path],
          screenshot_url: result[:cloudinary_secure_url],
          screenshot_cloudinary_public_id: result[:cloudinary_public_id],
          screenshot_cloudinary_version: result[:cloudinary_version],
          screenshot_cloudinary_format: result[:cloudinary_format],
          screenshot_width: result[:width],
          screenshot_height: result[:height]
        }

      {:error, reason} ->
        Logger.warning("Failed to upload story screenshot #{story_id}: #{inspect(reason)}")
        %{}
    end
  end

  defp upload_screenshot(_profile, _story), do: %{}
end
