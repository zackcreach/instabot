defmodule Instabot.Repo.Migrations.AddLocalMediaToStories do
  use Ecto.Migration

  def change do
    alter table(:stories) do
      add :media_path, :text
      add :media_content_type, :text
      add :media_file_size, :bigint
      add :media_sha256, :text
    end
  end
end
