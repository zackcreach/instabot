defmodule Instabot.Repo.Migrations.CreateProfileNotificationPreferences do
  use Instabot.Utils.Migrations

  def change do
    alter table(:email_digests) do
      add :tracked_profile_id, references(:tracked_profiles, type: :text, on_delete: :nilify_all)
    end

    create index(:email_digests, [:user_id, :digest_type, :tracked_profile_id])

    create table(:profile_notification_preferences, primary_key: false) do
      id("pnp")
      add :user_id, references(:users, type: :text, on_delete: :delete_all), null: false

      add :tracked_profile_id,
          references(:tracked_profiles, type: :text, on_delete: :delete_all),
          null: false

      add :frequency, :string, null: false, default: "inherit"
      add :include_images, :boolean
      add :include_ocr, :boolean

      timestamps(type: :utc_datetime)
    end

    create unique_index(:profile_notification_preferences, [:tracked_profile_id])
    create index(:profile_notification_preferences, [:user_id])
    create index(:profile_notification_preferences, [:frequency])
  end
end
