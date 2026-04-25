defmodule InstabotWeb.UnsubscribeController do
  use InstabotWeb, :controller

  alias Instabot.Notifications

  @token_max_age 30 * 24 * 60 * 60

  def show(conn, %{"token" => token}) do
    case verify_token(token) do
      {:ok, _user_id} ->
        render(conn, :show, token: token, error: nil)

      {:error, _reason} ->
        render(conn, :show, token: token, error: :invalid)
    end
  end

  def confirm(conn, %{"token" => token}) do
    case verify_token(token) do
      {:ok, user_id} ->
        Notifications.disable_notifications(user_id)
        render(conn, :confirmed)

      {:error, _reason} ->
        render(conn, :show, token: token, error: :invalid)
    end
  end

  defp verify_token(token) do
    Phoenix.Token.verify(InstabotWeb.Endpoint, "unsubscribe", token, max_age: @token_max_age)
  end
end
