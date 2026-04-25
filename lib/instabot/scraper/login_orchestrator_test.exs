defmodule Instabot.Scraper.LoginOrchestratorTest do
  use Instabot.DataCase

  import Instabot.AccountsFixtures

  alias Instabot.Instagram
  alias Instabot.Scraper.LoginOrchestrator

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

  defp collect_messages(timeout) do
    receive do
      message -> [message | collect_messages(timeout)]
    after
      timeout -> []
    end
  end

  describe "run/3 — successful login" do
    setup do
      configure_mock_bridge("success")
      user = user_fixture()
      subscribe_to_login(user.id)
      %{user: user}
    end

    @tag timeout: 30_000
    test "broadcasts step progression and saves cookies", %{user: user} do
      assert :ok == LoginOrchestrator.run(user.id, "testuser", "password123")

      messages = collect_messages(500)
      steps = for {:login_step, step} <- messages, do: step

      assert :launching in steps
      assert :navigating in steps
      assert :logging_in in steps
      assert :saving in steps
      assert :connected in steps

      screenshots = for {:login_screenshot, _base64} <- messages, do: :screenshot
      assert length(screenshots) > 0

      connection = Instagram.get_connection_for_user(user.id)
      assert "connected" == connection.status
      assert nil != connection.encrypted_cookies
    end

    @tag timeout: 30_000
    test "creates connection with connecting status during flow", %{user: user} do
      task =
        Task.async(fn ->
          LoginOrchestrator.run(user.id, "testuser", "password123")
        end)

      assert_receive {:login_step, :launching}, 5_000

      connection = Instagram.get_connection_for_user(user.id)
      assert "connecting" == connection.status
      assert "testuser" == connection.instagram_username

      Task.await(task, 25_000)
    end
  end

  describe "run/3 — login error" do
    setup do
      configure_mock_bridge("error")
      user = user_fixture()
      subscribe_to_login(user.id)
      %{user: user}
    end

    @tag timeout: 30_000
    test "broadcasts error on incorrect password", %{user: user} do
      assert {:error, :incorrect_password} ==
               LoginOrchestrator.run(user.id, "testuser", "wrongpassword")

      messages = collect_messages(500)
      errors = for {:login_error, reason} <- messages, do: reason
      assert :incorrect_password in errors
    end
  end

  describe "run/3 — two-factor authentication" do
    setup do
      configure_mock_bridge("two_factor")
      user = user_fixture()
      subscribe_to_login(user.id)
      %{user: user}
    end

    @tag timeout: 30_000
    test "handles 2FA flow with code submission", %{user: user} do
      task =
        Task.async(fn ->
          LoginOrchestrator.run(user.id, "testuser", "password123")
        end)

      assert_receive {:login_step, :two_factor}, 15_000

      send(task.pid, {:two_factor_code, "123456"})

      result = Task.await(task, 15_000)
      assert :ok == result

      messages = collect_messages(500)
      steps = for {:login_step, step} <- messages, do: step
      assert :connected in steps
    end
  end

  describe "run/3 — upsert behavior" do
    setup do
      configure_mock_bridge("success")
      user = user_fixture()
      subscribe_to_login(user.id)
      %{user: user}
    end

    @tag timeout: 30_000
    test "updates existing connection on re-connect", %{user: user} do
      {:ok, _connection} =
        Instagram.create_connection(user.id, %{
          instagram_username: "old_username",
          status: "expired"
        })

      assert :ok == LoginOrchestrator.run(user.id, "new_username", "password123")

      connection = Instagram.get_connection_for_user(user.id)
      assert "connected" == connection.status
      assert "new_username" == connection.instagram_username
    end
  end
end
