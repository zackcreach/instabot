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
    field :cloudinary_public_id, :string
    field :cloudinary_secure_url, :string
    field :cloudinary_version, :string
    field :cloudinary_format, :string
    field :cloudinary_resource_type, :string
    field :width, :integer
    field :height, :integer

    belongs_to :post, Instabot.Instagram.Post, type: UXID

    timestamps(type: :utc_datetime)
  end

  def changeset(post_image, attrs) do
    post_image
    |> cast(attrs, [
      :original_url,
      :local_path,
      :position,
      :content_type,
      :file_size,
      :cloudinary_public_id,
      :cloudinary_secure_url,
      :cloudinary_version,
      :cloudinary_format,
      :cloudinary_resource_type,
      :width,
      :height
    ])
    |> validate_required([:original_url, :post_id])
    |> validate_storage_location()
  end

  defp validate_storage_location(changeset) do
    case {get_field(changeset, :local_path), get_field(changeset, :cloudinary_secure_url)} do
      {local_path, _url} when is_binary(local_path) and local_path != "" -> changeset
      {_local_path, url} when is_binary(url) and url != "" -> changeset
      _ -> add_error(changeset, :local_path, "or cloudinary secure URL is required")
    end
  end
end
