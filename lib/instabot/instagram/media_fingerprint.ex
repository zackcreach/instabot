defmodule Instabot.Instagram.MediaFingerprint do
  @moduledoc false
  use Instabot.Schema, prefix: "mfp"

  import Ecto.Changeset

  @source_kinds ~w(post story)

  schema "media_fingerprints" do
    field :exact_sha256, :string
    field :dhash, :string
    field :source_kind, :string
    field :source_id, :string
    field :media_position, :integer, default: 0
    field :width, :integer
    field :height, :integer

    belongs_to :tracked_profile, Instabot.Instagram.TrackedProfile, type: UXID

    timestamps(type: :utc_datetime)
  end

  def changeset(media_fingerprint, attrs) do
    media_fingerprint
    |> cast(attrs, [
      :tracked_profile_id,
      :exact_sha256,
      :dhash,
      :source_kind,
      :source_id,
      :media_position,
      :width,
      :height
    ])
    |> validate_required([:tracked_profile_id, :exact_sha256, :dhash, :source_kind, :source_id, :media_position])
    |> validate_inclusion(:source_kind, @source_kinds)
  end
end
