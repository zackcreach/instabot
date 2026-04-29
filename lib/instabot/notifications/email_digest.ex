defmodule Instabot.Notifications.EmailDigest do
  @moduledoc false
  use Instabot.Schema, prefix: "edg"

  import Ecto.Changeset

  @digest_types ~w(immediate daily weekly)

  schema "email_digests" do
    field :digest_type, :string
    field :posts_count, :integer, default: 0
    field :stories_count, :integer, default: 0
    field :sent_at, :utc_datetime
    field :period_start, :utc_datetime
    field :period_end, :utc_datetime

    belongs_to :user, Instabot.Accounts.User, type: UXID
    belongs_to :tracked_profile, Instabot.Instagram.TrackedProfile, type: UXID

    timestamps(type: :utc_datetime)
  end

  def changeset(digest, attrs) do
    digest
    |> cast(attrs, [
      :digest_type,
      :posts_count,
      :stories_count,
      :sent_at,
      :period_start,
      :period_end,
      :tracked_profile_id
    ])
    |> validate_required([:digest_type, :user_id])
    |> validate_inclusion(:digest_type, @digest_types)
  end
end
