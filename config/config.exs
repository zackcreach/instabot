# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  instabot: [
    args:
      ~w(js/app.ts --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :instabot, Instabot.Mailer, adapter: Swoosh.Adapters.Local

config :instabot, Instabot.Repo,
  migration_primary_key: [name: :id, type: :text],
  migration_foreign_key: [type: :text],
  migration_timestamps: [type: :utc_datetime]

config :instabot, Instabot.Scraper,
  playwright_path: Path.expand("../assets/playwright", __DIR__),
  bridge_script: Path.expand("../assets/playwright/dist/playwright_bridge.js", __DIR__),
  node_path: "node",
  browser_timeout: 30_000,
  command_timeout: 60_000,
  screenshot_dir: Path.expand("../priv/static/screenshots", __DIR__)

# Configure the endpoint
config :instabot, InstabotWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: InstabotWeb.ErrorHTML, json: InstabotWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Instabot.PubSub,
  live_view: [signing_salt: "TABK35Xk"]

config :instabot, Oban,
  repo: Instabot.Repo,
  queues: [scraping: 2, media: 5, ocr: 3, notifications: 2],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"*/30 * * * *", Instabot.Workers.ScheduleScrapes},
       {"0 * * * *", Instabot.Workers.SendDailyDigests},
       {"0 8 * * 1", Instabot.Workers.SendWeeklyDigests}
     ]}
  ]

config :instabot, :scopes,
  user: [
    default: true,
    module: Instabot.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Instabot.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :instabot,
  ecto_repos: [Instabot.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  instabot: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),

    # Import environment specific config. This must remain at the bottom
    # of this file so it overrides the configuration defined above.
    cd: Path.expand("..", __DIR__)
  ]

import_config "#{config_env()}.exs"
