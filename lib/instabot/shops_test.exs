defmodule Instabot.ShopsTest do
  use Instabot.DataCase, async: true

  import Instabot.AccountsFixtures
  import Instabot.ShopsFixtures

  alias Instabot.Shops
  alias Instabot.Shops.ChangeDetector

  describe "sites" do
    test "creates a site with normalized URLs" do
      user = user_fixture()

      assert {:ok, site} =
               Shops.create_site(user.id, %{
                 name: "DTC Shop",
                 home_url: "example.com/",
                 product_url: "example.com/products/hat/"
               })

      assert "https://example.com" == site.home_url
      assert "https://example.com/products/hat" == site.product_url
    end

    test "lists due active sites using each interval" do
      user = user_fixture()
      now = ~U[2026-05-05 18:00:00Z]
      due = shopify_site_fixture(user, %{home_url: "https://due.test", scrape_interval_minutes: 60})
      fresh = shopify_site_fixture(user, %{home_url: "https://fresh.test", scrape_interval_minutes: 60})

      {:ok, _due} =
        due
        |> Ecto.Changeset.change(%{last_scraped_at: ~U[2026-05-05 16:59:00Z]})
        |> Repo.update()

      {:ok, _fresh} =
        fresh
        |> Ecto.Changeset.change(%{last_scraped_at: ~U[2026-05-05 17:30:00Z]})
        |> Repo.update()

      site_ids = now |> Shops.list_due_active_sites() |> Enum.map(& &1.id)

      assert due.id in site_ids
      refute fresh.id in site_ids
    end
  end

  describe "snapshots and changes" do
    test "creates first snapshot change" do
      user = user_fixture()
      site = shopify_site_fixture(user)

      assert {:ok, {_snapshot, [change]}} =
               Shops.create_snapshot_with_changes(site, %{
                 screenshot_sha256: "one",
                 banner_text: "Welcome",
                 banner_sale_detected: false,
                 captured_at: ~U[2026-05-05 18:00:00Z]
               })

      assert "first_snapshot" == change.change_type
    end

    test "detects sale banner and product price changes" do
      user = user_fixture()
      site = shopify_site_fixture(user)

      shopify_snapshot_fixture(site, %{
        screenshot_sha256: "one",
        banner_text: "Free shipping",
        banner_sale_detected: false,
        product_price_cents: 3000,
        captured_at: ~U[2026-05-05 18:00:00Z]
      })

      assert {:ok, {_snapshot, changes}} =
               Shops.create_snapshot_with_changes(site, %{
                 screenshot_sha256: "two",
                 banner_text: "25% off everything",
                 banner_sale_detected: true,
                 product_price_cents: 2400,
                 captured_at: ~U[2026-05-05 19:00:00Z]
               })

      change_types = Enum.map(changes, & &1.change_type)

      assert "screenshot_changed" in change_types
      assert "sale_banner_started" in change_types
      assert "banner_text_changed" in change_types
      assert "product_price_changed" in change_types
    end

    test "recognizes sale text" do
      assert ChangeDetector.sale_banner?("Limited time 20% off")
      refute ChangeDetector.sale_banner?("New arrivals are here")
    end
  end
end
