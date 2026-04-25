defmodule Instabot.Notifications.NotificationPreference do
  @moduledoc false
  use Instabot.Schema, prefix: "ntp"

  import Ecto.Changeset

  @frequencies ~w(immediate daily weekly disabled)

  schema "notification_preferences" do
    field :frequency, :string, default: "disabled"
    field :daily_send_at, :time
    field :weekly_send_day, :integer
    field :email_address, :string
    field :include_images, :boolean, default: true
    field :include_ocr, :boolean, default: true

    belongs_to :user, Instabot.Accounts.User, type: UXID

    timestamps(type: :utc_datetime)
  end

  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [
      :frequency,
      :daily_send_at,
      :weekly_send_day,
      :email_address,
      :include_images,
      :include_ocr
    ])
    |> validate_required([:frequency, :user_id])
    |> validate_inclusion(:frequency, @frequencies)
    |> validate_inclusion(:weekly_send_day, 1..7)
    |> validate_format(:email_address, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "must be a valid email")
    |> unique_constraint(:user_id)
  end
end
