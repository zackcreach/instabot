defmodule Instabot.Instagram.InstagramConnection do
  @moduledoc false
  use Instabot.Schema, prefix: "igc"

  import Ecto.Changeset

  @statuses ~w(disconnected connecting connected expired)

  schema "instagram_connections" do
    field :instagram_username, :string
    field :encrypted_cookies, :binary
    field :encrypted_password, :binary
    field :status, :string, default: "disconnected"
    field :cookies_expire_at, :utc_datetime
    field :last_login_at, :utc_datetime

    belongs_to :user, Instabot.Accounts.User, type: UXID

    timestamps(type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :instagram_username,
      :encrypted_cookies,
      :encrypted_password,
      :status,
      :cookies_expire_at,
      :last_login_at
    ])
    |> validate_required([:instagram_username, :user_id])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:user_id)
  end
end
