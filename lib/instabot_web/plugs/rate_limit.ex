defmodule InstabotWeb.Plugs.RateLimit do
  @moduledoc false
  import Plug.Conn

  def init(opts) do
    scale_ms = Keyword.fetch!(opts, :scale_ms)
    limit = Keyword.fetch!(opts, :limit)
    key_func = Keyword.get(opts, :key_func, &default_key/1)
    {scale_ms, limit, key_func}
  end

  def call(conn, {scale_ms, limit, key_func}) do
    if Application.get_env(:instabot, :rate_limiting_enabled, true) do
      key = key_func.(conn)
      check_rate(conn, key, scale_ms, limit)
    else
      conn
    end
  end

  defp check_rate(conn, key, scale_ms, limit) do
    case Hammer.check_rate(key, scale_ms, limit) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(429, "Too many requests. Please try again later.")
        |> halt()
    end
  end

  defp default_key(conn) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    "rate_limit:#{conn.request_path}:#{ip}"
  end
end
