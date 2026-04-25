import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# In test we don't send emails
config :instabot, Instabot.Mailer, adapter: Swoosh.Adapters.Test

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :instabot, Instabot.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "instabot_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :instabot, Instabot.Scraper,
  playwright_path: Path.expand("../assets/playwright", __DIR__),
  node_path: "node",
  browser_timeout: 5_000,
  command_timeout: 5_000,
  screenshot_dir: Path.expand("../priv/static/screenshots_test", __DIR__)

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :instabot, InstabotWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "+kdy5F2bcdc+iOe/P5w76SHxZpeuRkY7PcSIz3OkpDk6aezBgRRcxdQC3Q48BNby",
  server: false

config :instabot, Oban, testing: :manual
config :instabot, :rate_limiting_enabled, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false
