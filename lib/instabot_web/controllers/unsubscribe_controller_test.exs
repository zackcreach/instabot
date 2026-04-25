defmodule InstabotWeb.UnsubscribeControllerTest do
  use InstabotWeb.ConnCase, async: true

  import Instabot.AccountsFixtures

  @token_salt "unsubscribe"

  defp valid_token(user_id) do
    Phoenix.Token.sign(InstabotWeb.Endpoint, @token_salt, user_id)
  end

  defp expired_token(user_id) do
    Phoenix.Token.sign(InstabotWeb.Endpoint, @token_salt, user_id,
      signed_at: System.system_time(:second) - 31 * 24 * 60 * 60
    )
  end

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "GET /unsubscribe/:token" do
    test "renders confirmation page with valid token", %{conn: conn, user: user} do
      token = valid_token(user.id)

      conn = get(conn, ~p"/unsubscribe/#{token}")

      assert html_response(conn, 200) =~ "Unsubscribe"
    end

    test "renders error state with invalid token", %{conn: conn} do
      conn = get(conn, ~p"/unsubscribe/not_a_real_token")

      assert html_response(conn, 200) =~ "invalid"
    end

    test "renders error state with expired token", %{conn: conn, user: user} do
      token = expired_token(user.id)

      conn = get(conn, ~p"/unsubscribe/#{token}")

      assert html_response(conn, 200) =~ "invalid"
    end
  end

  describe "POST /unsubscribe/:token" do
    test "disables notifications and renders confirmed page with valid token", %{conn: conn, user: user} do
      token = valid_token(user.id)

      conn = post(conn, ~p"/unsubscribe/#{token}")

      assert html_response(conn, 200) =~ "unsubscribed"

      preference = Instabot.Notifications.get_preference_for_user(user.id)
      assert %{frequency: "disabled"} = preference
    end

    test "renders error state with invalid token", %{conn: conn} do
      conn = post(conn, ~p"/unsubscribe/not_a_real_token")

      assert html_response(conn, 200) =~ "invalid"
    end
  end
end
