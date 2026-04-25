defmodule Instabot.Scraper.Session do
  @moduledoc """
  Cookie management and login flow orchestration for Instagram scraping sessions.
  Stateless module that operates against a Browser GenServer process.
  """

  alias Instabot.Encryption
  alias Instabot.Instagram
  alias Instabot.Instagram.InstagramConnection
  alias Instabot.Scraper.AntiDetection
  alias Instabot.Scraper.Browser
  alias Instabot.Scraper.Parser

  @instagram_url "https://www.instagram.com/"

  @doc """
  Creates a new browser page and restores the full session state (cookies + localStorage)
  from the connection. Uses Playwright storageState for complete session restoration.
  Returns `{:ok, page_id}` or `{:error, reason}`.
  """
  @spec setup_session(pid(), InstagramConnection.t()) ::
          {:ok, String.t()} | {:error, term()}
  def setup_session(browser_pid, %InstagramConnection{} = connection) do
    with {:ok, session_data} <- decrypt_session_data(connection) do
      restore_session(browser_pid, session_data)
    end
  end

  @doc """
  Verifies the current session is valid by navigating to Instagram
  and checking for login redirects.
  Returns `:ok` or `{:error, :session_expired}`.
  """
  @spec verify_session(pid(), String.t(), InstagramConnection.t()) ::
          :ok | {:error, :session_expired}
  def verify_session(browser_pid, page_id, %InstagramConnection{} = connection) do
    with {:ok, _} <- Browser.navigate(browser_pid, page_id, @instagram_url),
         {:ok, html} <- Browser.get_page_content(browser_pid, page_id) do
      if Parser.login_page?(html) do
        Instagram.mark_connection_expired(connection)
        {:error, :session_expired}
      else
        :ok
      end
    end
  end

  @doc """
  Captures full storage state (cookies + localStorage) from the browser and stores it
  encrypted in the InstagramConnection. Supersedes the old cookies-only approach.
  Returns `{:ok, connection}` or `{:error, reason}`.
  """
  @spec save_cookies(pid(), String.t(), InstagramConnection.t()) ::
          {:ok, InstagramConnection.t()} | {:error, term()}
  def save_cookies(browser_pid, page_id, %InstagramConnection{} = connection) do
    with {:ok, storage_state} <- Browser.get_storage_state(browser_pid, page_id) do
      encrypted = Encryption.encrypt_term(storage_state)
      expires_at = DateTime.add(DateTime.utc_now(), 90, :day)
      Instagram.store_cookies(connection, encrypted, expires_at)
    end
  end

  @doc """
  Creates a new browser page and restores session from already-decrypted session data.
  Accepts either a storageState map (new format) or a cookie list (legacy format).
  Returns `{:ok, page_id}` or `{:error, reason}`.
  """
  @spec setup_session_from_data(pid(), map() | [map()]) ::
          {:ok, String.t()} | {:error, term()}
  def setup_session_from_data(browser_pid, session_data) do
    restore_session(browser_pid, session_data)
  end

  # --- Private ---

  defp decrypt_session_data(%InstagramConnection{encrypted_cookies: nil}) do
    {:error, :no_cookies}
  end

  defp decrypt_session_data(%InstagramConnection{encrypted_cookies: encrypted}) do
    Encryption.decrypt_term(encrypted)
  end

  defp restore_session(browser_pid, storage_state) when is_map(storage_state) do
    with {:ok, page_id} <-
           Browser.new_page(browser_pid,
             user_agent: AntiDetection.random_user_agent(),
             viewport: AntiDetection.random_viewport()
           ),
         {:ok, _} <- Browser.restore_storage_state(browser_pid, page_id, storage_state) do
      {:ok, page_id}
    end
  end

  defp restore_session(browser_pid, cookies) when is_list(cookies) do
    with {:ok, page_id} <-
           Browser.new_page(browser_pid,
             user_agent: AntiDetection.random_user_agent(),
             viewport: AntiDetection.random_viewport()
           ),
         {:ok, _} <- Browser.set_cookies(browser_pid, page_id, cookies) do
      {:ok, page_id}
    end
  end
end
