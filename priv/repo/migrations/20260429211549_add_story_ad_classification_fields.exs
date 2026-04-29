defmodule Instabot.Repo.Migrations.AddStoryAdClassificationFields do
  use Ecto.Migration

  def change do
    alter table(:stories) do
      add :story_chrome_detected, :boolean
      add :likely_ad, :boolean, null: false, default: false
      add :ad_score, :integer, null: false, default: 0
      add :ad_reasons, {:array, :string}, null: false, default: []
    end
  end
end
