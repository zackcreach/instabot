defmodule InstabotWeb.Router do
  use InstabotWeb, :router

  import InstabotWeb.UserAuth
  import Phoenix.LiveDashboard.Router

  alias InstabotWeb.Plugs.RateLimit

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {InstabotWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; " <>
          "img-src 'self' data: https:; connect-src 'self' wss:; font-src 'self'"
    }

    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :rate_limit_auth do
    plug RateLimit, scale_ms: 60_000, limit: 5
  end

  pipeline :rate_limit_unsubscribe do
    plug RateLimit, scale_ms: 60_000, limit: 10
  end

  scope "/admin" do
    pipe_through [:browser, :require_authenticated_user]

    live_dashboard "/dashboard", metrics: InstabotWeb.Telemetry
  end

  if Application.compile_env(:instabot, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", InstabotWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{InstabotWeb.UserAuth, :require_authenticated}] do
      live "/", DashboardLive, :index
      live "/feed", FeedLive, :index
      live "/feed/posts/:id", FeedLive, :show
      live "/feed/stories", StoriesLive, :index
      live "/feed/stories/:id", StoriesLive, :show
      live "/profiles", ProfilesLive, :index
      live "/profiles/new", ProfilesLive, :new
      live "/connect", ConnectLive, :index
      live "/settings/notifications", NotificationSettingsLive, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", InstabotWeb do
    pipe_through [:browser, :rate_limit_auth]

    live_session :current_user,
      on_mount: [{InstabotWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
  end

  scope "/", InstabotWeb do
    pipe_through [:browser]

    delete "/users/log-out", UserSessionController, :delete
  end

  scope "/", InstabotWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  scope "/", InstabotWeb do
    pipe_through [:browser, :rate_limit_unsubscribe]

    get "/unsubscribe/:token", UnsubscribeController, :show
    post "/unsubscribe/:token", UnsubscribeController, :confirm
  end
end
