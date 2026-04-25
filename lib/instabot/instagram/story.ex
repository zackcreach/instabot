defmodule Instabot.Instagram.Story do
  @moduledoc false
  use Instabot.Schema, prefix: "str"

  import Ecto.Changeset

  @ocr_statuses ~w(pending processing completed failed)
  @story_types ~w(image video)

  schema "stories" do
    field :instagram_story_id, :string
    field :screenshot_path, :string
    field :ocr_text, :string
    field :ocr_status, :string, default: "pending"
    field :story_type, :string
    field :media_url, :string
    field :posted_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :tracked_profile, Instabot.Instagram.TrackedProfile, type: UXID

    timestamps(type: :utc_datetime)
  end

  def changeset(story, attrs) do
    story
    |> cast(attrs, [
      :instagram_story_id,
      :screenshot_path,
      :ocr_text,
      :ocr_status,
      :story_type,
      :media_url,
      :posted_at,
      :expires_at
    ])
    |> validate_required([:tracked_profile_id, :instagram_story_id])
    |> validate_inclusion(:ocr_status, @ocr_statuses)
    |> validate_inclusion(:story_type, @story_types)
    |> unique_constraint([:tracked_profile_id, :instagram_story_id])
  end
end
