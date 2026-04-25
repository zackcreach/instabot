defmodule InstabotWeb.ConnectLiveTest do
  use InstabotWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "mount" do
    test "renders credentials form at idle step", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/connect")

      assert html =~ "Connect Instagram"
      assert html =~ "Enter your Instagram credentials"
      assert html =~ "Instagram username"
      assert html =~ "Password"
    end

    test "shows step indicator with all steps", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/connect")

      assert html =~ "Credentials"
      assert html =~ "Login"
      assert html =~ "2FA"
      assert html =~ "Done"
    end

    test "shows back button linking to dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      assert has_element?(view, "a[href='/']", "Back")
    end
  end

  describe "PubSub messages" do
    test "updates step on login_step message", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      Phoenix.PubSub.broadcast(
        Instabot.PubSub,
        "instagram_login:#{user.id}",
        {:login_step, :navigating}
      )

      html = render(view)
      assert html =~ "Opening Instagram..."
    end

    test "displays screenshot on login_screenshot message", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      Phoenix.PubSub.broadcast(
        Instabot.PubSub,
        "instagram_login:#{user.id}",
        {:login_step, :navigating}
      )

      fake_screenshot = Base.encode64("fake_png_data")

      Phoenix.PubSub.broadcast(
        Instabot.PubSub,
        "instagram_login:#{user.id}",
        {:login_screenshot, fake_screenshot}
      )

      assert has_element?(view, "#login-screenshot")
    end

    test "shows error display on login_error message", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      Phoenix.PubSub.broadcast(
        Instabot.PubSub,
        "instagram_login:#{user.id}",
        {:login_error, :incorrect_password}
      )

      html = render(view)
      assert html =~ "Login Failed"
      assert html =~ "The password you entered is incorrect."
      assert html =~ "Try Again"
    end

    test "shows 2FA form on two_factor step", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      Phoenix.PubSub.broadcast(
        Instabot.PubSub,
        "instagram_login:#{user.id}",
        {:login_step, :two_factor}
      )

      html = render(view)
      assert html =~ "Two-Factor Authentication"
      assert html =~ "6-digit code"
      assert html =~ "Verify Code"
    end

    test "shows success display on connected step", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      Phoenix.PubSub.broadcast(
        Instabot.PubSub,
        "instagram_login:#{user.id}",
        {:login_step, :connected}
      )

      html = render(view)
      assert html =~ "Connected!"
      assert html =~ "Go to Dashboard"
    end
  end

  describe "retry" do
    test "resets to idle step with credentials form", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      Phoenix.PubSub.broadcast(
        Instabot.PubSub,
        "instagram_login:#{user.id}",
        {:login_error, :login_failed}
      )

      assert render(view) =~ "Login Failed"

      view |> element("button", "Try Again") |> render_click()

      html = render(view)
      assert html =~ "Enter your Instagram credentials"
      refute html =~ "Login Failed"
    end
  end

  describe "validate_credentials event" do
    test "updates form state on input change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      html =
        view
        |> form("#credentials-form", %{credentials: %{username: "myuser", password: "mypass"}})
        |> render_change()

      assert html =~ "myuser"
    end
  end

  describe "retry state cleanup" do
    test "clears screenshot and error on retry", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/connect")
      topic = "instagram_login:#{user.id}"

      Phoenix.PubSub.broadcast(Instabot.PubSub, topic, {:login_screenshot, Base.encode64("png")})
      Phoenix.PubSub.broadcast(Instabot.PubSub, topic, {:login_error, :login_failed})

      html = render(view)
      assert html =~ "Login Failed"
      assert html =~ "login-screenshot"

      view |> element("button", "Try Again") |> render_click()

      html = render(view)
      assert html =~ "Enter your Instagram credentials"
      refute html =~ "Login Failed"
      refute html =~ "login-screenshot"
    end
  end

  describe "task crash handling" do
    test "ignores DOWN messages from unknown tasks", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      unknown_ref = make_ref()
      unknown_pid = spawn(fn -> :ok end)

      send(view.pid, {:DOWN, unknown_ref, :process, unknown_pid, :killed})

      html = render(view)
      assert html =~ "Enter your Instagram credentials"
      refute html =~ "Login Failed"
    end
  end

  describe "step indicator styling" do
    test "idle step shows credentials as primary, rest as base", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/connect")

      assert html =~ "bg-primary"
      assert html =~ "bg-base-300"
    end

    for {step, expected_classes} <- [
          {:navigating, ["bg-success", "bg-base-300"]},
          {:logging_in, ["bg-success", "bg-primary", "bg-base-300"]},
          {:two_factor, ["bg-success", "bg-primary", "bg-base-300"]},
          {:connected, ["bg-success", "bg-primary"]},
          {:error, ["bg-error"]}
        ] do
      test "#{step} step shows correct dot colors", %{conn: conn, user: user} do
        {:ok, view, _html} = live(conn, ~p"/connect")

        Phoenix.PubSub.broadcast(
          Instabot.PubSub,
          "instagram_login:#{user.id}",
          {:login_step, unquote(step)}
        )

        html = render(view)

        for expected_class <- unquote(expected_classes) do
          assert html =~ expected_class
        end
      end
    end

    test "error step turns all four dots to bg-error", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/connect")

      Phoenix.PubSub.broadcast(
        Instabot.PubSub,
        "instagram_login:#{user.id}",
        {:login_error, :login_failed}
      )

      html = render(view)
      dot_error_count = length(Regex.scan(~r/rounded-full transition-colors bg-error/, html))
      assert 4 == dot_error_count

      refute html =~ "rounded-full transition-colors bg-primary"
      refute html =~ "rounded-full transition-colors bg-success"
    end
  end

  describe "loading state rendering" do
    for {step, label} <- [
          {:launching, "Starting browser..."},
          {:navigating, "Opening Instagram..."},
          {:logging_in, "Entering credentials..."},
          {:saving, "Saving session..."}
        ] do
      test "#{step} shows spinner with label and screenshot if present", %{conn: conn, user: user} do
        {:ok, view, _html} = live(conn, ~p"/connect")
        topic = "instagram_login:#{user.id}"

        Phoenix.PubSub.broadcast(Instabot.PubSub, topic, {:login_screenshot, Base.encode64("img")})
        Phoenix.PubSub.broadcast(Instabot.PubSub, topic, {:login_step, unquote(step)})

        html = render(view)
        assert html =~ unquote(label)
        assert html =~ "loading-spinner"
        assert html =~ "login-screenshot"
      end
    end
  end

  describe "error messages" do
    for {error, expected_message} <- [
          {:incorrect_password, "The password you entered is incorrect."},
          {:username_not_found, "The username was not found."},
          {:rate_limited, "Too many attempts. Please wait a few minutes."},
          {:suspicious_attempt, "Instagram flagged this as suspicious."},
          {:challenge_required, "Instagram requires additional verification."},
          {:two_factor_failed, "The 2FA code was incorrect."},
          {:two_factor_timeout, "2FA code entry timed out."},
          {:task_crashed, "An unexpected error occurred."},
          {:login_failed, "Login failed. Please check your credentials."}
        ] do
      test "displays correct message for #{error}", %{conn: conn, user: user} do
        {:ok, view, _html} = live(conn, ~p"/connect")

        Phoenix.PubSub.broadcast(
          Instabot.PubSub,
          "instagram_login:#{user.id}",
          {:login_error, unquote(error)}
        )

        assert render(view) =~ unquote(expected_message)
      end
    end
  end
end
