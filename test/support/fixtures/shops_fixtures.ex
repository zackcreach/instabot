defmodule Instabot.ShopsFixtures do
  @moduledoc """
  Test helpers for Shopify monitoring records.
  """

  alias Instabot.Shops

  def shopify_site_fixture(user, attrs \\ %{}) do
    site_attrs =
      Map.merge(
        %{
          name: "Example Shop",
          home_url: "https://example-shop.test",
          product_url: "https://example-shop.test/products/widget"
        },
        attrs
      )

    {:ok, site} = Shops.create_site(user.id, site_attrs)
    site
  end

  def shopify_snapshot_fixture(site, attrs \\ %{}) do
    snapshot_attrs =
      Map.merge(
        %{
          screenshot_sha256: "snapshot-#{System.unique_integer([:positive])}",
          banner_text: "Free shipping",
          banner_sale_detected: false,
          captured_at: DateTime.utc_now(:second)
        },
        attrs
      )

    {:ok, {snapshot, _changes}} = Shops.create_snapshot_with_changes(site, snapshot_attrs)
    snapshot
  end
end
