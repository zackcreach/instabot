defmodule Instabot.Repo.Migrations.AddScrapeIntervalToTrackedProfiles do
  use Ecto.Migration

  def change do
    alter table(:tracked_profiles) do
      add :scrape_interval_minutes, :integer, default: 30, null: false
    end

    create constraint(:tracked_profiles, :tracked_profiles_scrape_interval_minutes_allowed,
             check: "scrape_interval_minutes IN (30, 60, 360, 720, 1440)"
           )
  end
end
