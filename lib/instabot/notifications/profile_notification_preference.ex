defmodule Instabot.Notifications.ProfileNotificationPreference do
  @moduledoc false
  use Instabot.Schema, prefix: "pnp"

  import Ecto.Changeset

  @frequencies ~w(inherit immediate daily weekly disabled)

  schema "profile_notification_preferences" do
    field :frequency, :string, default: "inherit"
    field :include_images, :boolean
    field :include_ocr, :boolean

    belongs_to :user, Instabot.Accounts.User, type: UXID
    belongs_to :tracked_profile, Instabot.Instagram.TrackedProfile, type: UXID

    timestamps(type: :utc_datetime)
  end

  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [:frequency, :include_images, :include_ocr])
    |> validate_required([:frequency, :user_id, :tracked_profile_id])
    |> validate_inclusion(:frequency, @frequencies)
    |> unique_constraint(:tracked_profile_id)
  end
end
