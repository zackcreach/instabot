defmodule Instabot.Repo.Migrations.AddPostImagePositionIntegrity do
  use Ecto.Migration

  def change do
    alter table(:post_images) do
      add :exact_sha256, :text
    end

    create unique_index(:post_images, [:post_id, :position])
    create unique_index(:media_fingerprints, [:source_kind, :source_id, :media_position])
  end
end
