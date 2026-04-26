import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/instabot start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :instabot, InstabotWeb.Endpoint, server: true
end

port = String.to_integer(System.get_env("PORT", "4000"))

scraper_config = Application.get_env(:instabot, Instabot.Scraper, [])

scraper_config =
  case System.get_env("INSTABOT_PLAYWRIGHT_PATH") do
    nil -> scraper_config
    playwright_path -> Keyword.put(scraper_config, :playwright_path, playwright_path)
  end

scraper_config =
  case System.get_env("INSTABOT_BRIDGE_SCRIPT") do
    nil -> scraper_config
    bridge -> Keyword.put(scraper_config, :bridge_script, bridge)
  end

scraper_config =
  case System.get_env("INSTABOT_SCREENSHOT_DIR") do
    nil -> scraper_config
    screenshot_dir -> Keyword.put(scraper_config, :screenshot_dir, screenshot_dir)
  end

config :instabot, Instabot.Scraper, scraper_config
config :instabot, InstabotWeb.Endpoint, http: [port: port]

case System.get_env("INSTABOT_UPLOADS_DIR") do
  nil -> :ok
  uploads_dir -> config :instabot, :uploads_dir, uploads_dir
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  scheme = System.get_env("PHX_SCHEME") || "http"
  url_port = String.to_integer(System.get_env("PHX_PORT") || Integer.to_string(port))

  check_origin =
    "PHX_CHECK_ORIGIN"
    |> System.get_env("#{scheme}://#{host}:#{url_port}")
    |> String.split(",", trim: true)

  mailgun_api_key =
    System.get_env("MAILGUN_API_KEY") ||
      raise "environment variable MAILGUN_API_KEY is missing."

  mailgun_domain =
    System.get_env("MAILGUN_DOMAIN") ||
      raise "environment variable MAILGUN_DOMAIN is missing."

  from_email = System.get_env("MAILGUN_FROM_EMAIL", "noreply@#{mailgun_domain}")

  config :instabot, Instabot.Mailer,
    adapter: Swoosh.Adapters.Mailgun,
    api_key: mailgun_api_key,
    domain: mailgun_domain

  config :instabot, Instabot.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # ## SSL Support
    # pool_count: 4,
    #
    # To get SSL working, you will need to add the `https` key
    # to your endpoint configuration:
    socket_options: maybe_ipv6

  config :instabot, InstabotWeb.Endpoint,
    url: [host: host, port: url_port, scheme: scheme],
    check_origin: check_origin,
    http: [
      # Enable IPv6 and bind on all interfaces.
      #
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      #     config :instabot, InstabotWeb.Endpoint,
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      #       https: [
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      #         ...,
      #         port: 443,
      #         cipher_suite: :strong,
      #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
      #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
      #       ]
      #
      # The `cipher_suite` is set to `:strong` to support only the
      # latest and more secure SSL ciphers. This means old browsers
      # and clients may not be supported. You can set it to
      # `:compatible` for wider support.
      #
      # `:keyfile` and `:certfile` expect an absolute path to the key
      # and cert in disk or a relative path inside priv, for example
      # "priv/ssl/server.key". For all supported SSL configuration
      # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1

      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :instabot, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
  config :instabot, :from_email, from_email
end
