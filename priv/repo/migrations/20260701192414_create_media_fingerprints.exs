defmodule Instabot.Repo.Migrations.CreateMediaFingerprints do
  use Instabot.Utils.Migrations

  def change do
    alter table(:scrape_logs) do
      add :duplicate_posts_found, :integer, null: false, default: 0
      add :duplicate_stories_found, :integer, null: false, default: 0
    end

    create table(:media_fingerprints, primary_key: false) do
      id("mfp")

      add :tracked_profile_id,
          references(:tracked_profiles, type: :text, on_delete: :delete_all),
          null: false

      add :exact_sha256, :text, null: false
      add :dhash, :text, null: false
      add :source_kind, :text, null: false
      add :source_id, :text, null: false
      add :media_position, :integer, null: false, default: 0
      add :width, :integer
      add :height, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:media_fingerprints, [:tracked_profile_id])
    create index(:media_fingerprints, [:tracked_profile_id, :exact_sha256])
    create index(:media_fingerprints, [:tracked_profile_id, :source_kind, :source_id])
  end
end
