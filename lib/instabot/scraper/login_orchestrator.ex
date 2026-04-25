defmodule Instabot.Scraper.LoginOrchestrator do
  @moduledoc """
  Orchestrates the Instagram login flow via Playwright.
  Stateless module designed to run inside `Task.async` from ConnectLive.
  Communicates progress back via PubSub broadcasts on topic `"instagram_login:{user_id}"`.
  """

  alias Instabot.Encryption
  alias Instabot.Instagram
  alias Instabot.Scraper.AntiDetection
  alias Instabot.Scraper.Browser
  alias Instabot.Scraper.Parser
  alias Instabot.Scraper.Session
  alias Instabot.Scraper.Supervisor, as: ScraperSupervisor

  require Logger

  @login_url "https://www.instagram.com/accounts/login/"
  @username_selector ~s(input[name="email"], input[name="username"])
  @password_selector ~s(input[name="pass"], input[name="password"])
  @submit_selector "button[type=\"submit\"]"
  @two_factor_selector "input[name=\"verificationCode\"]"
  @typing_delay 75
  @two_factor_timeout 120_000

  @doc """
  Runs the full Instagram login flow.
  Designed to execute inside `Task.async` — broadcasts step updates via PubSub
  and receives 2FA codes via direct message from the caller.
  """
  @spec run(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def run(user_id, username, password) do
    topic = "instagram_login:#{user_id}"

    with {:ok, connection} <- upsert_connecting(user_id, username, password),
         {:ok, browser, page_id} <- start_browser(topic) do
      try do
        perform_login(browser, page_id, username, password, topic, connection)
      after
        try do
          Browser.stop(browser)
        catch
          :exit, _ -> :ok
        end
      end
    else
      {:error, reason} ->
        broadcast(topic, {:login_error, reason})
        {:error, reason}
    end
  end

  defp upsert_connecting(user_id, username, password) do
    encrypted_password = Encryption.encrypt_term(password)

    Instagram.upsert_connection(user_id, %{
      instagram_username: username,
      encrypted_password: encrypted_password,
      status: "connecting"
    })
  end

  defp start_browser(topic) do
    broadcast(topic, {:login_step, :launching})

    with {:ok, browser} <- ScraperSupervisor.start_browser(),
         {:ok, _} <- Browser.launch(browser, AntiDetection.launch_options()),
         {:ok, page_id} <-
           Browser.new_page(browser,
             user_agent: AntiDetection.random_user_agent(),
             viewport: AntiDetection.random_viewport()
           ) do
      {:ok, browser, page_id}
    end
  end

  defp perform_login(browser, page_id, username, password, topic, connection) do
    with :ok <- navigate_to_login(browser, page_id, topic),
         :ok <- enter_credentials(browser, page_id, username, password, topic),
         :ok <- submit_and_handle_result(browser, page_id, topic, connection) do
      :ok
    else
      {:error, reason} ->
        broadcast(topic, {:login_error, reason})
        {:error, reason}
    end
  end

  defp navigate_to_login(browser, page_id, topic) do
    broadcast(topic, {:login_step, :navigating})
    AntiDetection.wait(1_000, 2_000)

    with {:ok, _} <- Browser.navigate(browser, page_id, @login_url, wait_until: "load", timeout: 45_000),
         :ok <- dismiss_cookie_dialog(browser, page_id),
         {:ok, _} <- Browser.wait_for_selector(browser, page_id, @username_selector) do
      broadcast_screenshot(browser, page_id, topic)
      :ok
    end
  end

  defp dismiss_cookie_dialog(browser, page_id) do
    dismiss_js = """
    (() => {
      const buttons = document.querySelectorAll('button');
      for (const button of buttons) {
        const text = button.textContent.toLowerCase();
        if (text.includes('allow') && text.includes('cookie')) {
          button.click();
          return 'dismissed';
        }
      }
      for (const button of buttons) {
        const text = button.textContent.toLowerCase();
        if (text.includes('accept') || text.includes('allow all') || text.includes('decline optional')) {
          button.click();
          return 'dismissed';
        }
      }
      return 'not_found';
    })()
    """

    case Browser.evaluate(browser, page_id, dismiss_js) do
      {:ok, "dismissed"} ->
        AntiDetection.wait(1_000, 2_000)
        :ok

      _ ->
        :ok
    end
  end

  defp enter_credentials(browser, page_id, username, password, topic) do
    broadcast(topic, {:login_step, :logging_in})
    AntiDetection.wait(500, 1_500)

    with {:ok, _} <-
           Browser.type_text(browser, page_id, @username_selector, username, delay: @typing_delay),
         _ = AntiDetection.wait(300, 800),
         {:ok, _} <-
           Browser.type_text(browser, page_id, @password_selector, password, delay: @typing_delay) do
      broadcast_screenshot(browser, page_id, topic)
      :ok
    end
  end

  defp submit_and_handle_result(browser, page_id, topic, connection) do
    AntiDetection.wait(500, 1_000)

    with {:ok, _} <- submit_login_form(browser, page_id) do
      AntiDetection.wait(3_000, 5_000)

      with {:ok, html} <- Browser.get_page_content(browser, page_id) do
        broadcast_screenshot(browser, page_id, topic)
        handle_post_submit(browser, page_id, html, topic, connection)
      end
    end
  end

  defp handle_post_submit(browser, page_id, html, topic, connection) do
    cond do
      Parser.two_factor_page?(html) and has_two_factor_input?(browser, page_id) ->
        handle_two_factor(browser, page_id, topic, connection)

      Parser.logged_in_page?(html) ->
        save_session(browser, page_id, topic, connection)

      Parser.login_page?(html) ->
        case Parser.login_error?(html) do
          {:error, reason} -> {:error, reason}
          :ok -> {:error, :login_failed}
        end

      true ->
        case Parser.login_error?(html) do
          {:error, reason} -> {:error, reason}
          :ok -> save_session(browser, page_id, topic, connection)
        end
    end
  end

  defp has_two_factor_input?(browser, page_id) do
    case Browser.wait_for_selector(browser, page_id, @two_factor_selector, timeout: 3_000) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp submit_login_form(browser, page_id) do
    Browser.keyboard_press(browser, page_id, "Enter")
  end

  defp handle_two_factor(browser, page_id, topic, connection) do
    broadcast(topic, {:login_step, :two_factor})

    receive do
      {:two_factor_code, code} ->
        submit_two_factor(browser, page_id, code, topic, connection)
    after
      @two_factor_timeout ->
        {:error, :two_factor_timeout}
    end
  end

  defp submit_two_factor(browser, page_id, code, topic, connection) do
    with {:ok, _} <-
           Browser.type_text(browser, page_id, @two_factor_selector, code, delay: @typing_delay) do
      AntiDetection.wait(500, 1_000)

      with {:ok, _} <- Browser.click(browser, page_id, @submit_selector) do
        AntiDetection.wait(3_000, 5_000)

        with {:ok, html} <- Browser.get_page_content(browser, page_id) do
          broadcast_screenshot(browser, page_id, topic)

          cond do
            Parser.logged_in_page?(html) ->
              save_session(browser, page_id, topic, connection)

            Parser.two_factor_page?(html) or Parser.login_page?(html) ->
              {:error, :two_factor_failed}

            true ->
              case Parser.login_error?(html) do
                {:error, reason} -> {:error, reason}
                :ok -> save_session(browser, page_id, topic, connection)
              end
          end
        end
      end
    end
  end

  defp save_session(browser, page_id, topic, connection) do
    broadcast(topic, {:login_step, :saving})

    case Session.save_cookies(browser, page_id, connection) do
      {:ok, _connection} ->
        broadcast(topic, {:login_step, :connected})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(Instabot.PubSub, topic, message)
  end

  defp broadcast_screenshot(browser, page_id, topic) do
    case Browser.screenshot(browser, page_id) do
      {:ok, %{"base64" => base64}} ->
        broadcast(topic, {:login_screenshot, base64})

      {:error, _} ->
        :ok
    end
  end
end
