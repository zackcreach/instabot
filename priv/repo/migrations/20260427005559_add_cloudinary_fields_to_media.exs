defmodule Instabot.Repo.Migrations.AddCloudinaryFieldsToMedia do
  use Ecto.Migration

  def change do
    alter table(:post_images) do
      modify :local_path, :string, null: true, from: {:string, null: false}
      add :cloudinary_public_id, :text
      add :cloudinary_secure_url, :text
      add :cloudinary_version, :string
      add :cloudinary_format, :string
      add :cloudinary_resource_type, :string
      add :width, :integer
      add :height, :integer
    end

    alter table(:stories) do
      add :screenshot_url, :text
      add :screenshot_cloudinary_public_id, :text
      add :screenshot_cloudinary_version, :string
      add :screenshot_cloudinary_format, :string
      add :screenshot_width, :integer
      add :screenshot_height, :integer
    end
  end
end
