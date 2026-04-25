defmodule Instabot.Instagram.PostImage do
  @moduledoc false
  use Instabot.Schema, prefix: "pim"

  import Ecto.Changeset

  schema "post_images" do
    field :original_url, :string
    field :local_path, :string
    field :position, :integer, default: 0
    field :content_type, :string
    field :file_size, :integer

    belongs_to :post, Instabot.Instagram.Post, type: UXID

    timestamps(type: :utc_datetime)
  end

  def changeset(post_image, attrs) do
    post_image
    |> cast(attrs, [:original_url, :local_path, :position, :content_type, :file_size])
    |> validate_required([:original_url, :local_path, :post_id])
  end
end
