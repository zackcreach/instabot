defmodule Instabot.Repo.Migrations.CreateShopifyMonitoringTables do
  use Instabot.Utils.Migrations

  def change do
    create table(:shopify_sites, primary_key: false) do
      id("shs")
      add :user_id, references(:users, type: :text, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :home_url, :text, null: false
      add :product_url, :text
      add :is_active, :boolean, null: false, default: true
      add :last_scraped_at, :utc_datetime
      add :scrape_interval_minutes, :integer, null: false, default: 30

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shopify_sites, [:user_id, :home_url])
    create index(:shopify_sites, [:user_id])
    create index(:shopify_sites, [:is_active])

    create table(:shopify_snapshots, primary_key: false) do
      id("shp")

      add :shopify_site_id, references(:shopify_sites, type: :text, on_delete: :delete_all),
        null: false

      add :screenshot_url, :text
      add :screenshot_path, :text
      add :screenshot_sha256, :string, null: false
      add :screenshot_cloudinary_public_id, :string
      add :screenshot_cloudinary_version, :string
      add :screenshot_cloudinary_format, :string
      add :screenshot_width, :integer
      add :screenshot_height, :integer
      add :banner_text, :text
      add :banner_sale_detected, :boolean, null: false, default: false
      add :product_title, :string
      add :product_price_cents, :integer
      add :product_compare_at_price_cents, :integer
      add :product_currency, :string
      add :product_available, :boolean
      add :captured_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:shopify_snapshots, [:shopify_site_id, :captured_at])

    create table(:shopify_changes, primary_key: false) do
      id("shc")

      add :shopify_site_id, references(:shopify_sites, type: :text, on_delete: :delete_all),
        null: false

      add :previous_snapshot_id,
          references(:shopify_snapshots, type: :text, on_delete: :nilify_all)

      add :snapshot_id, references(:shopify_snapshots, type: :text, on_delete: :delete_all),
        null: false

      add :change_type, :string, null: false
      add :summary, :text, null: false
      add :metadata, :map, null: false, default: %{}
      add :detected_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:shopify_changes, [:shopify_site_id, :detected_at])
    create index(:shopify_changes, [:snapshot_id])
  end
end
