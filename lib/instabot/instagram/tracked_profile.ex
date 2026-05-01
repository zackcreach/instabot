defmodule Instabot.Instagram.TrackedProfile do
  @moduledoc false
  use Instabot.Schema, prefix: "tpr"

  import Ecto.Changeset

  @scrape_interval_minutes [30, 60, 360, 720, 1440]

  schema "tracked_profiles" do
    field :instagram_username, :string
    field :display_name, :string
    field :profile_pic_url, :string
    field :is_active, :boolean, default: true
    field :last_scraped_at, :utc_datetime
    field :scrape_interval_minutes, :integer, default: 30

    belongs_to :user, Instabot.Accounts.User, type: UXID
    has_many :posts, Instabot.Instagram.Post
    has_many :stories, Instabot.Instagram.Story
    has_many :scrape_logs, Instabot.Instagram.ScrapeLog
    has_one :profile_notification_preference, Instabot.Notifications.ProfileNotificationPreference

    timestamps(type: :utc_datetime)
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:instagram_username, :display_name, :profile_pic_url, :is_active, :scrape_interval_minutes])
    |> validate_required([:instagram_username, :user_id, :scrape_interval_minutes])
    |> validate_format(:instagram_username, ~r/^[a-zA-Z0-9._]+$/,
      message: "must only contain letters, numbers, periods, and underscores"
    )
    |> validate_length(:instagram_username, max: 30)
    |> validate_length(:display_name, max: 200)
    |> validate_inclusion(:scrape_interval_minutes, @scrape_interval_minutes)
    |> unique_constraint([:user_id, :instagram_username], error_key: :instagram_username)
  end

  def scrape_interval_minutes, do: @scrape_interval_minutes
end
