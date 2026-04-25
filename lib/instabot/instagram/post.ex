defmodule Instabot.Instagram.Post do
  @moduledoc false
  use Instabot.Schema, prefix: "pst"

  import Ecto.Changeset

  @post_types ~w(image video carousel reel)

  schema "posts" do
    field :instagram_post_id, :string
    field :caption, :string
    field :hashtags, {:array, :string}, default: []
    field :posted_at, :utc_datetime
    field :post_type, :string
    field :media_urls, {:array, :string}, default: []
    field :permalink, :string

    belongs_to :tracked_profile, Instabot.Instagram.TrackedProfile, type: UXID
    has_many :post_images, Instabot.Instagram.PostImage

    timestamps(type: :utc_datetime)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [
      :instagram_post_id,
      :caption,
      :hashtags,
      :posted_at,
      :post_type,
      :media_urls,
      :permalink
    ])
    |> validate_required([:instagram_post_id, :tracked_profile_id, :post_type])
    |> validate_inclusion(:post_type, @post_types)
    |> unique_constraint([:tracked_profile_id, :instagram_post_id])
  end
end
