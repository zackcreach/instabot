defmodule Instabot.Repo.Migrations.CreateInstagramTables do
  use Instabot.Utils.Migrations

  def change do
    create table(:instagram_connections, primary_key: false) do
      id("igc")
      add :user_id, references(:users, type: :text, on_delete: :delete_all), null: false
      add :instagram_username, :string, null: false
      add :encrypted_cookies, :binary
      add :encrypted_password, :binary
      add :status, :string, null: false, default: "disconnected"
      add :cookies_expire_at, :utc_datetime
      add :last_login_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:instagram_connections, [:user_id])

    create table(:tracked_profiles, primary_key: false) do
      id("tpr")
      add :user_id, references(:users, type: :text, on_delete: :delete_all), null: false
      add :instagram_username, :string, null: false
      add :display_name, :string
      add :profile_pic_url, :string
      add :is_active, :boolean, default: true, null: false
      add :last_scraped_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tracked_profiles, [:user_id, :instagram_username])
    create index(:tracked_profiles, [:user_id])

    create table(:posts, primary_key: false) do
      id("pst")

      add :tracked_profile_id,
          references(:tracked_profiles, type: :text, on_delete: :delete_all),
          null: false

      add :instagram_post_id, :string, null: false
      add :caption, :text
      add :hashtags, {:array, :string}, default: []
      add :posted_at, :utc_datetime
      add :post_type, :string
      add :media_urls, {:array, :string}, default: []
      add :permalink, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:posts, [:tracked_profile_id, :instagram_post_id])
    create index(:posts, [:tracked_profile_id])
    create index(:posts, [:posted_at])

    create table(:post_images, primary_key: false) do
      id("pim")
      add :post_id, references(:posts, type: :text, on_delete: :delete_all), null: false
      add :original_url, :string, null: false
      add :local_path, :string, null: false
      add :position, :integer, default: 0
      add :content_type, :string
      add :file_size, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:post_images, [:post_id])

    create table(:stories, primary_key: false) do
      id("str")

      add :tracked_profile_id,
          references(:tracked_profiles, type: :text, on_delete: :delete_all),
          null: false

      add :instagram_story_id, :string
      add :screenshot_path, :string
      add :ocr_text, :text
      add :ocr_status, :string, default: "pending"
      add :story_type, :string
      add :media_url, :string
      add :posted_at, :utc_datetime
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:stories, [:tracked_profile_id])
    create index(:stories, [:posted_at])
  end
end
