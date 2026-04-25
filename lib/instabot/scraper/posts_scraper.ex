defmodule Instabot.Scraper.PostsScraper do
  @moduledoc """
  Scrapes posts from an Instagram profile page.
  Orchestrates the Browser, Session, Parser, and Instagram context modules.
  """

  alias Instabot.Encryption
  alias Instabot.Instagram
  alias Instabot.Instagram.Events
  alias Instabot.Instagram.InstagramConnection
  alias Instabot.Instagram.TrackedProfile
  alias Instabot.Scraper.AntiDetection
  alias Instabot.Scraper.Browser
  alias Instabot.Scraper.Parser
  alias Instabot.Scraper.Session
  alias Instabot.Scraper.Supervisor, as: ScraperSupervisor

  require Logger

  @profile_url "https://www.instagram.com"
  @scroll_count 3
  @scroll_delay_min 1_500
  @scroll_delay_max 4_000
  @post_fetch_delay_min 2_000
  @post_fetch_delay_max 6_000

  @doc """
  Scrapes posts for the given username using the provided cookies.
  Returns `{:ok, %{posts: [post_map], profile_metadata: map()}}` or `{:error, reason}`.

  Each post_map contains: `:instagram_post_id`, `:caption`, `:hashtags`,
  `:posted_at`, `:post_type`, `:media_urls`, `:permalink`.
  """
  @spec scrape(String.t(), map() | [map()], keyword()) :: {:ok, map()} | {:error, term()}
  def scrape(username, session_data, opts \\ []) do
    max_posts = Keyword.get(opts, :max_posts, 12)

    with {:ok, browser} <- ScraperSupervisor.start_browser() do
      try do
        scrape_with_browser(browser, username, session_data, max_posts)
      after
        Browser.stop(browser)
      end
    end
  end

  @doc """
  Scrapes posts and persists them to the database for a tracked profile.
  Creates a scrape_log entry.
  Returns `{:ok, scrape_log}` or `{:error, reason}`.
  """
  @spec scrape_and_persist(TrackedProfile.t(), InstagramConnection.t(), keyword()) ::
          {:ok, Instagram.ScrapeLog.t()} | {:error, term()}
  def scrape_and_persist(%TrackedProfile{} = profile, %InstagramConnection{} = connection, opts \\ []) do
    case Instagram.create_scrape_log(profile.id, %{scrape_type: "posts"}) do
      {:ok, log} ->
        scrape_and_persist_with_log(profile, connection, log, opts)

      {:error, _reason} = error ->
        error
    end
  end

  # --- Private ---

  defp scrape_and_persist_with_log(profile, connection, log, opts) do
    with {:ok, session_data} <- Encryption.decrypt_term(connection.encrypted_cookies),
         {:ok, %{posts: posts, profile_metadata: profile_metadata}} <-
           scrape(profile.instagram_username, session_data, opts) do
      update_profile_metadata(profile, profile_metadata)
      persisted_count = persist_posts(profile, posts)
      Instagram.update_last_scraped(profile)
      Instagram.complete_scrape_log(log, %{posts_found: persisted_count})
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

  defp scrape_with_browser(browser, username, session_data, max_posts) do
    with {:ok, _} <- Browser.launch(browser, AntiDetection.launch_options()),
         {:ok, page_id} <- Session.setup_session_from_data(browser, session_data),
         :ok <- navigate_to_profile(browser, page_id, username),
         {:ok, html} <- scroll_and_collect(browser, page_id) do
      profile_metadata = Parser.extract_profile_metadata(html)
      post_refs = Parser.extract_posts_from_profile(html)
      limited_refs = Enum.take(post_refs, max_posts)

      with {:ok, posts} <- fetch_post_details(browser, page_id, limited_refs) do
        {:ok, %{posts: posts, profile_metadata: profile_metadata}}
      end
    end
  end

  defp navigate_to_profile(browser, page_id, username) do
    url = "#{@profile_url}/#{username}/"
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

  defp scroll_and_collect(browser, page_id) do
    scroll_js = "window.scrollTo(0, document.body.scrollHeight)"

    Enum.each(1..@scroll_count, fn _i ->
      Browser.evaluate(browser, page_id, scroll_js)
      AntiDetection.wait(@scroll_delay_min, @scroll_delay_max)
    end)

    Browser.get_page_content(browser, page_id)
  end

  defp fetch_post_details(browser, page_id, post_refs) do
    posts =
      Enum.reduce_while(post_refs, [], fn post_ref, acc ->
        AntiDetection.wait(@post_fetch_delay_min, @post_fetch_delay_max)

        case fetch_single_post(browser, page_id, post_ref) do
          {:ok, post} ->
            {:cont, [post | acc]}

          {:error, reason} ->
            Logger.warning("Failed to fetch post #{post_ref.instagram_post_id}: #{inspect(reason)}")

            {:cont, acc}
        end
      end)

    {:ok, Enum.reverse(posts)}
  end

  defp fetch_single_post(browser, page_id, post_ref) do
    with {:ok, _} <- Browser.navigate(browser, page_id, post_ref.permalink),
         {:ok, html} <- Browser.get_page_content(browser, page_id),
         {:ok, json_responses} <- Browser.get_json_responses(browser, page_id) do
      details =
        Parser.extract_post_details_from_responses(json_responses, post_ref.instagram_post_id) ||
          Parser.extract_post_details(html)

      {:ok,
       Map.merge(details, %{
         instagram_post_id: post_ref.instagram_post_id,
         permalink: post_ref.permalink
       })}
    end
  end

  defp persist_posts(profile, posts) do
    Enum.count(posts, fn post_attrs ->
      case Instagram.upsert_post_from_scrape(profile.id, post_attrs) do
        {:ok, post, status} when status in [:inserted, :updated] ->
          Events.broadcast_post_created(profile, post)
          true

        {:ok, _post, :unchanged} ->
          false

        {:error, _changeset} ->
          false
      end
    end)
  end

  defp update_profile_metadata(profile, metadata) do
    attrs =
      metadata
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> Map.new()

    case attrs do
      attrs when map_size(attrs) > 0 -> Instagram.update_tracked_profile_metadata(profile, attrs)
      _ -> {:ok, profile}
    end
  end
end
