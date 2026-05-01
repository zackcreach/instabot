defmodule InstabotWeb.NotificationSettingsLiveTest do
  use InstabotWeb.ConnCase, async: true

  import Instabot.InstagramFixtures
  import Phoenix.LiveViewTest

  alias Instabot.Notifications

  setup :register_and_log_in_user

  test "renders notification settings form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/settings/notifications")

    assert html =~ "Notification Settings"
    assert html =~ "Email Frequency"
    assert html =~ "Save Preferences"
  end

  test "defaults to disabled frequency", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/settings/notifications")

    assert html =~ ~s(value="disabled")
  end

  test "shows daily time input when frequency is daily", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/notifications")

    html =
      view
      |> form("#notification_form", notification_preference: %{frequency: "daily"})
      |> render_change()

    assert html =~ "Send daily digest at"
  end

  test "shows weekly options when frequency is weekly", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/notifications")

    html =
      view
      |> form("#notification_form", notification_preference: %{frequency: "weekly"})
      |> render_change()

    assert html =~ "Send weekly digest at"
    assert html =~ "Day of week"
  end

  test "hides time options when frequency is immediate", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/notifications")

    html =
      view
      |> form("#notification_form", notification_preference: %{frequency: "immediate"})
      |> render_change()

    refute html =~ "Send daily digest at"
    refute html =~ "Day of week"
  end

  test "saves preferences and shows success flash", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/notifications")

    html =
      view
      |> form("#notification_form", notification_preference: %{frequency: "immediate", include_images: true})
      |> render_submit()

    assert html =~ "Notification preferences saved."
  end

  test "saves content checkbox preferences", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/settings/notifications")

    view
    |> form("#notification_form",
      notification_preference: %{
        frequency: "daily",
        include_images: false,
        include_ocr: false
      }
    )
    |> render_submit()

    preference = Notifications.get_preference_for_user(user.id)

    assert false == preference.include_images
    assert false == preference.include_ocr
  end

  test "saves profile notification overrides", %{conn: conn, user: user} do
    profile = tracked_profile_fixture(user)
    {:ok, view, _html} = live(conn, ~p"/settings/notifications")

    view
    |> form("#notification_form",
      notification_preference: %{frequency: "daily"},
      profile_notification_preferences: %{
        profile.id => %{
          frequency: "immediate",
          include_images: "false",
          include_ocr: "inherit"
        }
      }
    )
    |> render_submit()

    preference = Notifications.get_profile_preference_for_profile(profile.id)

    assert "immediate" == preference.frequency
    assert false == preference.include_images
    assert nil == preference.include_ocr
  end

  test "renders profile overrides inside the page preferences form", %{conn: conn, user: user} do
    profile = tracked_profile_fixture(user)
    {:ok, view, _html} = live(conn, ~p"/settings/notifications")

    assert has_element?(view, "#notification_form #profile-notification-frequency-#{profile.id}")
    refute has_element?(view, "#profile-notification-form-#{profile.id}")
  end
end
