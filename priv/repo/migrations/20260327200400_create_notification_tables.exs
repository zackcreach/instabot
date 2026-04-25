defmodule Instabot.Repo.Migrations.CreateNotificationTables do
  use Instabot.Utils.Migrations

  def change do
    create table(:notification_preferences, primary_key: false) do
      id("ntp")
      add :user_id, references(:users, type: :text, on_delete: :delete_all), null: false
      add :frequency, :string, null: false, default: "disabled"
      add :daily_send_at, :time
      add :weekly_send_day, :integer
      add :email_address, :string
      add :include_images, :boolean, default: true, null: false
      add :include_ocr, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:notification_preferences, [:user_id])

    create table(:scrape_logs, primary_key: false) do
      id("slg")

      add :tracked_profile_id,
          references(:tracked_profiles, type: :text, on_delete: :delete_all),
          null: false

      add :scrape_type, :string, null: false
      add :status, :string, null: false, default: "started"
      add :posts_found, :integer, default: 0
      add :stories_found, :integer, default: 0
      add :error_message, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:scrape_logs, [:tracked_profile_id])

    create table(:email_digests, primary_key: false) do
      id("edg")
      add :user_id, references(:users, type: :text, on_delete: :delete_all), null: false
      add :digest_type, :string, null: false
      add :posts_count, :integer, default: 0
      add :stories_count, :integer, default: 0
      add :sent_at, :utc_datetime
      add :period_start, :utc_datetime
      add :period_end, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:email_digests, [:user_id])
  end
end
