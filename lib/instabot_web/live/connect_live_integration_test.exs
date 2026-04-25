defmodule InstabotWeb.ConnectLiveIntegrationTest do
  use InstabotWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Instabot.Instagram

  setup :register_and_log_in_user

  @login_mock_bridge_path Path.expand("../../../test/support/login_mock_bridge.js", __DIR__)

  defp configure_mock_bridge(mode) do
    original_config = Application.get_env(:instabot, Instabot.Scraper)
    original_mode = System.get_env("LOGIN_MOCK_MODE")
    node_path = System.find_executable("node")

    System.put_env("LOGIN_MOCK_MODE", mode)

    Application.put_env(:instabot, Instabot.Scraper,
      playwright_path: Path.dirname(@login_mock_bridge_path),
      node_path: node_path,
      bridge_script: @login_mock_bridge_path,
      browser_timeout: 10_000,
      command_timeout: 10_000
    )

    on_exit(fn ->
      Application.put_env(:instabot, Instabot.Scraper, original_config)

      if original_mode do
        System.put_env("LOGIN_MOCK_MODE", original_mode)
      else
        System.delete_env("LOGIN_MOCK_MODE")
      end
    end)
  end

  defp subscribe_to_login(user_id) do
    Phoenix.PubSub.subscribe(Instabot.PubSub, "instagram_login:#{user_id}")
  end

  defp submit_credentials(view, username, password) do
    view
    |> form("#credentials-form", %{credentials: %{username: username, password: password}})
    |> render_submit()
  end

  describe "success flow integration" do
    setup context do
      configure_mock_bridge("success")
      subscribe_to_login(context.user.id)
      :ok
    end

    @tag timeout: 30_000
    test "form submission progresses through all steps to connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      html = submit_credentials(view, "testuser", "password123")
      assert html =~ "Starting browser..."

      assert_receive {:login_step, :connected}, 20_000
      Process.sleep(100)

      html = render(view)
      assert html =~ "Connected!"
      assert html =~ "Go to Dashboard"
    end

    @tag timeout: 30_000
    test "creates connection record with connected status", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      submit_credentials(view, "successuser", "password123")

      assert_receive {:login_step, :launching}, 5_000
      connection_during_flow = Instagram.get_connection_for_user(user.id)
      assert %{status: "connecting", instagram_username: "successuser"} = connection_during_flow

      assert_receive {:login_step, :connected}, 20_000
      Process.sleep(100)

      connection_after_flow = Instagram.get_connection_for_user(user.id)
      assert %{status: "connected", instagram_username: "successuser"} = connection_after_flow
      assert connection_after_flow.encrypted_cookies
    end

    @tag timeout: 30_000
    test "broadcasts screenshots during flow", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      submit_credentials(view, "testuser", "password123")

      assert_receive {:login_screenshot, screenshot_data}, 15_000
      assert is_binary(screenshot_data)

      assert_receive {:login_step, :connected}, 20_000
      Process.sleep(100)

      assert render(view) =~ "Connected!"
    end

    @tag timeout: 30_000
    test "step indicator progresses through expected steps", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      submit_credentials(view, "testuser", "password123")

      assert_receive {:login_step, :launching}, 5_000
      assert_receive {:login_step, :navigating}, 5_000
      assert_receive {:login_step, :logging_in}, 5_000
      assert_receive {:login_step, :saving}, 10_000
      assert_receive {:login_step, :connected}, 5_000

      Process.sleep(100)
      html = render(view)
      assert html =~ "bg-success"
      assert html =~ "bg-primary"
      refute html =~ "bg-error"
    end
  end

  describe "error flow integration" do
    setup context do
      configure_mock_bridge("error")
      subscribe_to_login(context.user.id)
      :ok
    end

    @tag timeout: 30_000
    test "displays error message on incorrect password", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      submit_credentials(view, "testuser", "wrongpassword")

      assert_receive {:login_error, :incorrect_password}, 20_000
      Process.sleep(100)

      html = render(view)
      assert html =~ "Login Failed"
      assert html =~ "The password you entered is incorrect."
      assert html =~ "Try Again"
      assert html =~ "bg-error"
    end

    @tag timeout: 30_000
    test "retry resets to idle and allows re-submission", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      submit_credentials(view, "testuser", "wrongpassword")

      assert_receive {:login_error, :incorrect_password}, 20_000
      Process.sleep(100)

      view |> element("button", "Try Again") |> render_click()

      html = render(view)
      assert html =~ "Enter your Instagram credentials"
      refute html =~ "Login Failed"

      submit_credentials(view, "testuser", "wrongpassword2")

      assert_receive {:login_error, :incorrect_password}, 20_000
      Process.sleep(100)

      assert render(view) =~ "Login Failed"
    end
  end

  describe "two-factor flow integration" do
    setup context do
      configure_mock_bridge("two_factor")
      subscribe_to_login(context.user.id)
      :ok
    end

    @tag timeout: 45_000
    test "pauses at 2FA, accepts code, completes to connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      submit_credentials(view, "testuser", "password123")

      assert_receive {:login_step, :two_factor}, 20_000
      Process.sleep(100)

      html = render(view)
      assert html =~ "Two-Factor Authentication"
      assert html =~ "6-digit code"
      assert html =~ "Verify Code"

      view
      |> form("#two-factor-form", %{two_factor: %{code: "123456"}})
      |> render_submit()

      assert_receive {:login_step, :connected}, 20_000
      Process.sleep(100)

      html = render(view)
      assert html =~ "Connected!"
      assert html =~ "Go to Dashboard"
    end

    @tag timeout: 45_000
    test "creates connected record after 2FA completion", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      submit_credentials(view, "twofa_user", "password123")

      assert_receive {:login_step, :two_factor}, 20_000
      Process.sleep(100)

      view
      |> form("#two-factor-form", %{two_factor: %{code: "654321"}})
      |> render_submit()

      assert_receive {:login_step, :connected}, 20_000
      Process.sleep(100)

      connection = Instagram.get_connection_for_user(user.id)
      assert %{status: "connected", instagram_username: "twofa_user"} = connection
    end
  end
end
