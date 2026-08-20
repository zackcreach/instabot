defmodule Instabot.Scraper.BrowserTest do
  use ExUnit.Case

  alias Instabot.Scraper.Browser

  @mock_bridge_path Path.expand("../../../test/support/dist/mock_bridge.js", __DIR__)

  defp start_mock_browser do
    original_config = Application.get_env(:instabot, Instabot.Scraper)
    node_path = System.find_executable("node")

    Application.put_env(:instabot, Instabot.Scraper,
      playwright_path: Path.dirname(@mock_bridge_path),
      node_path: node_path,
      bridge_script: @mock_bridge_path,
      browser_timeout: 5_000,
      command_timeout: 5_000
    )

    result = Browser.start_link()

    on_exit(fn ->
      Application.put_env(:instabot, Instabot.Scraper, original_config)
    end)

    result
  end

  describe "start_link/1" do
    test "starts the GenServer and opens a port" do
      {:ok, pid} = start_mock_browser()
      assert Process.alive?(pid)
      Browser.stop(pid)
    end
  end

  describe "launch/2" do
    test "sends launch command and receives response" do
      {:ok, pid} = start_mock_browser()
      {:ok, data} = Browser.launch(pid)
      assert %{"browser_version" => "mock-1.0"} = data
      Browser.stop(pid)
    end
  end

  describe "new_page/2" do
    test "creates a new page and returns page_id" do
      {:ok, pid} = start_mock_browser()
      {:ok, _} = Browser.launch(pid)
      {:ok, page_id} = Browser.new_page(pid)
      assert is_binary(page_id)
      Browser.stop(pid)
    end
  end

  describe "navigate/4" do
    test "navigates to a URL and returns page info" do
      {:ok, pid} = start_mock_browser()
      {:ok, _} = Browser.launch(pid)
      {:ok, page_id} = Browser.new_page(pid)
      {:ok, data} = Browser.navigate(pid, page_id, "https://example.com")
      assert %{"url" => "https://example.com", "title" => "Mock Page"} = data
      Browser.stop(pid)
    end
  end

  describe "get_page_content/2" do
    test "returns HTML content of the page" do
      {:ok, pid} = start_mock_browser()
      {:ok, _} = Browser.launch(pid)
      {:ok, page_id} = Browser.new_page(pid)
      {:ok, content} = Browser.get_page_content(pid, page_id)
      assert is_binary(content)
      assert String.contains?(content, "Mock content")
      Browser.stop(pid)
    end
  end

  describe "screenshot/3" do
    test "returns base64-encoded screenshot data" do
      {:ok, pid} = start_mock_browser()
      {:ok, _} = Browser.launch(pid)
      {:ok, page_id} = Browser.new_page(pid)
      {:ok, data} = Browser.screenshot(pid, page_id)
      assert %{"base64" => base64} = data
      assert is_binary(base64)
      Browser.stop(pid)
    end

    test "passes clip options to the bridge" do
      {:ok, pid} = start_mock_browser()
      {:ok, _} = Browser.launch(pid)
      {:ok, page_id} = Browser.new_page(pid)
      {:ok, data} = Browser.screenshot(pid, page_id, clip: %{x: 10, y: 20, width: 300, height: 400})
      assert %{"base64" => base64} = data
      assert "fake_clipped_png_data" == Base.decode64!(base64)
      Browser.stop(pid)
    end
  end

  describe "set_cookies/3 and get_cookies/2" do
    test "sets and retrieves cookies" do
      {:ok, pid} = start_mock_browser()
      {:ok, _} = Browser.launch(pid)
      {:ok, page_id} = Browser.new_page(pid)

      cookies = [%{name: "test", value: "value", domain: ".example.com"}]
      {:ok, _} = Browser.set_cookies(pid, page_id, cookies)

      {:ok, retrieved} = Browser.get_cookies(pid, page_id)
      assert is_list(retrieved)
      Browser.stop(pid)
    end
  end

  describe "evaluate/3" do
    test "evaluates JS expression and returns result" do
      {:ok, pid} = start_mock_browser()
      {:ok, _} = Browser.launch(pid)
      {:ok, page_id} = Browser.new_page(pid)
      {:ok, _result} = Browser.evaluate(pid, page_id, "1 + 1")
      Browser.stop(pid)
    end
  end

  describe "close/2" do
    test "closes without error" do
      {:ok, pid} = start_mock_browser()
      {:ok, _} = Browser.launch(pid)
      {:ok, _} = Browser.close(pid)
      Browser.stop(pid)
    end
  end

  describe "stop/1" do
    test "stops the GenServer" do
      {:ok, pid} = start_mock_browser()
      :ok = Browser.stop(pid)
      refute Process.alive?(pid)
      :ok = Browser.stop(pid)
    end

    test "waits for bridge descendants to exit" do
      child_pid_path =
        Path.join(System.tmp_dir!(), "instabot-mock-bridge-child-#{System.unique_integer([:positive])}")

      System.put_env("INSTABOT_MOCK_BRIDGE_CHILD_PID_PATH", child_pid_path)

      on_exit(fn ->
        System.delete_env("INSTABOT_MOCK_BRIDGE_CHILD_PID_PATH")
        File.rm(child_pid_path)
      end)

      {:ok, pid} = start_mock_browser()
      {:ok, _data} = Browser.launch(pid)
      child_pid = child_pid_path |> File.read!() |> String.trim()
      assert {_output, 0} = System.cmd("kill", ["-0", child_pid], stderr_to_stdout: true)

      :ok = Browser.stop(pid)

      assert {_output, exit_status} = System.cmd("kill", ["-0", child_pid], stderr_to_stdout: true)
      refute 0 == exit_status
    end
  end
end
