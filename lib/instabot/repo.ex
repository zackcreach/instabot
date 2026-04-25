defmodule Instabot.Repo do
  use Ecto.Repo,
    otp_app: :instabot,
    adapter: Ecto.Adapters.Postgres
end
