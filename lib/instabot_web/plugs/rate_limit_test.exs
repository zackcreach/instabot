defmodule InstabotWeb.Plugs.RateLimitTest do
  use InstabotWeb.ConnCase, async: true

  alias InstabotWeb.Plugs.RateLimit

  setup do
    Application.put_env(:instabot, :rate_limiting_enabled, true)
    on_exit(fn -> Application.put_env(:instabot, :rate_limiting_enabled, false) end)
  end

  defp unique_key_func do
    key = "test:#{System.unique_integer([:positive])}"
    fn _conn -> key end
  end

  test "allows requests under the limit" do
    opts = RateLimit.init(scale_ms: 60_000, limit: 3, key_func: unique_key_func())
    conn = build_conn()

    for _ <- 1..3 do
      result = RateLimit.call(conn, opts)
      refute result.halted
    end
  end

  test "blocks requests over the limit with 429" do
    opts = RateLimit.init(scale_ms: 60_000, limit: 2, key_func: unique_key_func())
    conn = build_conn()

    RateLimit.call(conn, opts)
    RateLimit.call(conn, opts)

    result = RateLimit.call(conn, opts)
    assert result.halted
    assert result.status == 429
  end

  test "uses separate buckets for different keys" do
    key_func_a = fn _conn -> "test:a:#{System.unique_integer([:positive])}" end
    key_func_b = fn _conn -> "test:b:#{System.unique_integer([:positive])}" end

    opts_a = RateLimit.init(scale_ms: 60_000, limit: 1, key_func: key_func_a)
    opts_b = RateLimit.init(scale_ms: 60_000, limit: 1, key_func: key_func_b)

    conn = build_conn()

    result_a = RateLimit.call(conn, opts_a)
    result_b = RateLimit.call(conn, opts_b)

    refute result_a.halted
    refute result_b.halted
  end
end
