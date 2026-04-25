defmodule Instabot.Scraper.AntiDetectionTest do
  use ExUnit.Case, async: true

  alias Instabot.Scraper.AntiDetection

  describe "random_delay/2" do
    test "returns a value within the default range" do
      for _i <- 1..100 do
        delay = AntiDetection.random_delay()
        assert delay >= 2_000
        assert delay <= 8_000
      end
    end

    test "returns a value within a custom range" do
      for _i <- 1..100 do
        delay = AntiDetection.random_delay(500, 1_000)
        assert delay >= 500
        assert delay <= 1_000
      end
    end

    test "returns exact value when min equals max" do
      assert 5_000 == AntiDetection.random_delay(5_000, 5_000)
    end
  end

  describe "random_user_agent/0" do
    test "returns a non-empty string" do
      user_agent = AntiDetection.random_user_agent()
      assert is_binary(user_agent)
      assert String.length(user_agent) > 0
    end

    test "returns a string containing Mozilla" do
      user_agent = AntiDetection.random_user_agent()
      assert String.contains?(user_agent, "Mozilla")
    end

    test "returns different values over multiple calls" do
      agents = for _i <- 1..50, do: AntiDetection.random_user_agent()
      assert length(Enum.uniq(agents)) > 1
    end
  end

  describe "random_viewport/0" do
    test "returns a map with width and height keys" do
      viewport = AntiDetection.random_viewport()
      assert %{width: width, height: height} = viewport
      assert is_integer(width)
      assert is_integer(height)
      assert width > 0
      assert height > 0
    end

    test "returns different values over multiple calls" do
      viewports = for _i <- 1..50, do: AntiDetection.random_viewport()
      assert length(Enum.uniq(viewports)) > 1
    end
  end

  describe "chromium_args/0" do
    test "includes automation detection bypass" do
      args = AntiDetection.chromium_args()
      assert "--disable-blink-features=AutomationControlled" in args
    end

    test "returns a list of strings" do
      args = AntiDetection.chromium_args()
      assert is_list(args)
      assert Enum.all?(args, &is_binary/1)
    end
  end

  describe "launch_options/1" do
    test "returns default headless mode enabled" do
      %{headless: true} = AntiDetection.launch_options()
    end

    test "includes chromium args by default" do
      options = AntiDetection.launch_options()
      assert "--disable-blink-features=AutomationControlled" in options.args
    end

    test "allows overriding headless mode" do
      %{headless: false} = AntiDetection.launch_options(headless: false)
    end
  end
end
