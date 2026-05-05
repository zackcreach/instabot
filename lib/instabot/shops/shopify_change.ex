defmodule Instabot.Shops.ShopifyChange do
  @moduledoc false
  use Instabot.Schema, prefix: "shc"

  import Ecto.Changeset

  alias Instabot.Shops.ShopifySnapshot

  @change_types ~w(
    first_snapshot
    screenshot_changed
    sale_banner_started
    sale_banner_ended
    banner_text_changed
    product_price_changed
    product_compare_at_price_changed
    product_availability_changed
  )

  schema "shopify_changes" do
    field :change_type, :string
    field :summary, :string
    field :metadata, :map, default: %{}
    field :detected_at, :utc_datetime

    belongs_to :shopify_site, Instabot.Shops.ShopifySite, type: UXID
    belongs_to :previous_snapshot, ShopifySnapshot, type: UXID
    belongs_to :snapshot, ShopifySnapshot, type: UXID

    timestamps(type: :utc_datetime)
  end

  def changeset(change, attrs) do
    change
    |> cast(attrs, [:previous_snapshot_id, :change_type, :summary, :metadata, :detected_at])
    |> validate_required([:shopify_site_id, :snapshot_id, :change_type, :summary, :detected_at])
    |> validate_inclusion(:change_type, @change_types)
  end
end
