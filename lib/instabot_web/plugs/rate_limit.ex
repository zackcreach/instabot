defmodule InstabotWeb.Plugs.RateLimit do
  @moduledoc false
  import Plug.Conn

  @forwarded_for_header "x-forwarded-for"

  def init(opts) do
    scale_ms = Keyword.fetch!(opts, :scale_ms)
    limit = Keyword.fetch!(opts, :limit)
    key_func = Keyword.get(opts, :key_func, {__MODULE__, :default_key})
    {scale_ms, limit, key_func}
  end

  def call(conn, {scale_ms, limit, key_func}) do
    if Application.get_env(:instabot, :rate_limiting_enabled, true) do
      key = rate_limit_key(key_func, conn)
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

  def default_key(conn) do
    ip =
      conn
      |> client_ip()
      |> :inet.ntoa()
      |> to_string()

    "rate_limit:#{conn.request_path}:#{ip}"
  end

  defp client_ip(%{remote_ip: remote_ip} = conn) when remote_ip in [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}] do
    conn
    |> get_req_header(@forwarded_for_header)
    |> forwarded_ip(remote_ip)
  end

  defp client_ip(conn), do: conn.remote_ip

  defp forwarded_ip([header | _headers], fallback) do
    header
    |> String.split(",")
    |> List.first()
    |> parse_ip(fallback)
  end

  defp forwarded_ip([], fallback), do: fallback

  defp parse_ip(nil, fallback), do: fallback

  defp parse_ip(value, fallback) do
    value
    |> String.trim()
    |> String.to_charlist()
    |> :inet.parse_address()
    |> case do
      {:ok, ip} -> ip
      {:error, :einval} -> fallback
    end
  end

  defp rate_limit_key({module, function}, conn) do
    apply(module, function, [conn])
  end

  defp rate_limit_key(key_func, conn) do
    key_func.(conn)
  end
end
