defmodule Instabot.Shops.ShopifySnapshot do
  @moduledoc false
  use Instabot.Schema, prefix: "shp"

  import Ecto.Changeset

  schema "shopify_snapshots" do
    field :screenshot_url, :string
    field :screenshot_path, :string
    field :screenshot_sha256, :string
    field :screenshot_cloudinary_public_id, :string
    field :screenshot_cloudinary_version, :string
    field :screenshot_cloudinary_format, :string
    field :screenshot_width, :integer
    field :screenshot_height, :integer
    field :banner_text, :string
    field :banner_sale_detected, :boolean, default: false
    field :product_title, :string
    field :product_price_cents, :integer
    field :product_compare_at_price_cents, :integer
    field :product_currency, :string
    field :product_available, :boolean
    field :captured_at, :utc_datetime

    belongs_to :shopify_site, Instabot.Shops.ShopifySite, type: UXID
    has_many :changes, Instabot.Shops.ShopifyChange, foreign_key: :snapshot_id

    timestamps(type: :utc_datetime)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :screenshot_url,
      :screenshot_path,
      :screenshot_sha256,
      :screenshot_cloudinary_public_id,
      :screenshot_cloudinary_version,
      :screenshot_cloudinary_format,
      :screenshot_width,
      :screenshot_height,
      :banner_text,
      :banner_sale_detected,
      :product_title,
      :product_price_cents,
      :product_compare_at_price_cents,
      :product_currency,
      :product_available,
      :captured_at
    ])
    |> validate_required([:shopify_site_id, :screenshot_sha256, :captured_at])
    |> validate_number(:product_price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:product_compare_at_price_cents, greater_than_or_equal_to: 0)
  end
end
