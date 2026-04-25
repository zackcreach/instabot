defmodule InstabotWeb.HealthController do
  use InstabotWeb, :controller

  def index(conn, _params) do
    case Ecto.Adapters.SQL.query(Instabot.Repo, "SELECT 1") do
      {:ok, _} ->
        json(conn, %{status: "ok"})

      {:error, _} ->
        conn
        |> put_status(503)
        |> json(%{status: "error", reason: "database unavailable"})
    end
  end
end
