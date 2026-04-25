defmodule Instabot.Scraper.AntiDetection do
  @moduledoc """
  Anti-detection utilities for browser scraping.
  Provides random delays, user agent rotation, and viewport configuration.
  """

  @user_agents [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:134.0) Gecko/20100101 Firefox/134.0"
  ]

  @viewports [
    %{width: 1920, height: 1080},
    %{width: 1440, height: 900},
    %{width: 1536, height: 864},
    %{width: 1366, height: 768},
    %{width: 1280, height: 720}
  ]

  @chromium_args [
    "--disable-blink-features=AutomationControlled",
    "--disable-dev-shm-usage",
    "--no-sandbox",
    "--no-first-run",
    "--no-default-browser-check"
  ]

  @doc "Returns a random delay in milliseconds between `min_ms` and `max_ms`."
  @spec random_delay(pos_integer(), pos_integer()) :: pos_integer()
  def random_delay(min_ms \\ 2_000, max_ms \\ 8_000) do
    min_ms + :rand.uniform(max_ms - min_ms + 1) - 1
  end

  @doc "Sleeps for a random delay between `min_ms` and `max_ms`."
  @spec wait(pos_integer(), pos_integer()) :: :ok
  def wait(min_ms \\ 2_000, max_ms \\ 8_000) do
    Process.sleep(random_delay(min_ms, max_ms))
  end

  @doc "Returns a random user agent string."
  @spec random_user_agent() :: String.t()
  def random_user_agent, do: Enum.random(@user_agents)

  @doc "Returns a random viewport size map with `:width` and `:height`."
  @spec random_viewport() :: %{width: pos_integer(), height: pos_integer()}
  def random_viewport, do: Enum.random(@viewports)

  @doc "Returns the base Chromium launch arguments for anti-detection."
  @spec chromium_args() :: [String.t()]
  def chromium_args, do: @chromium_args

  @doc "Returns launch options map with anti-detection defaults applied."
  @spec launch_options(keyword()) :: map()
  def launch_options(overrides \\ []) do
    defaults = %{
      headless: true,
      args: @chromium_args
    }

    Map.merge(defaults, Map.new(overrides))
  end
end
