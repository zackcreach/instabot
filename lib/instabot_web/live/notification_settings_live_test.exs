defmodule InstabotWeb.NotificationSettingsLiveTest do
  use InstabotWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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
end
