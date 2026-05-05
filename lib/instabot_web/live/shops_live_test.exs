defmodule InstabotWeb.ShopsLiveTest do
  use InstabotWeb.ConnCase, async: true
  use Oban.Testing, repo: Instabot.Repo

  import Instabot.ShopsFixtures
  import Phoenix.LiveViewTest

  alias Instabot.Repo
  alias Instabot.Shops
  alias Instabot.Workers.ScrapeShopifySite

  setup :register_and_log_in_user

  describe "mount" do
    test "renders empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shops")

      assert has_element?(view, "#show-shopify-site-form")
      assert render(view) =~ "No Shopify monitors yet"
    end

    test "renders tracked sites with latest snapshot", %{conn: conn, user: user} do
      site = shopify_site_fixture(user, %{name: "Hat Shop"})

      shopify_snapshot_fixture(site, %{
        screenshot_path: "priv/static/uploads/shopify/site.png",
        banner_text: "20% off hats",
        banner_sale_detected: true,
        product_price_cents: 1999,
        product_currency: "USD"
      })

      {:ok, view, _html} = live(conn, ~p"/shops")

      assert has_element?(view, "#shopify-site-#{site.id}")
      assert render(view) =~ "Hat Shop"
      assert render(view) =~ "USD 19.99"
    end
  end

  describe "save_site event" do
    test "creates a Shopify site and enqueues initial scrape", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/shops")

      view
      |> element("#show-shopify-site-form")
      |> render_click()

      view
      |> form("#add-shopify-site-form", %{
        "shopify_site" => %{
          "name" => "Sale Shop",
          "home_url" => "https://sale-shop.test",
          "product_url" => "https://sale-shop.test/products/jacket"
        }
      })
      |> render_submit()

      site = Shops.get_site_for_user!(user.id, Repo.get_by!(Instabot.Shops.ShopifySite, name: "Sale Shop").id)

      assert_enqueued(worker: ScrapeShopifySite, args: %{shopify_site_id: site.id})
      assert render(view) =~ "Sale Shop added and scrape queued."
    end
  end

  describe "scrape_now event" do
    test "enqueues a scrape job", %{conn: conn, user: user} do
      site = shopify_site_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/shops")

      view
      |> element("button[phx-click=scrape_now][phx-value-id=#{site.id}]")
      |> render_click()

      assert_enqueued(worker: ScrapeShopifySite, args: %{shopify_site_id: site.id})
      assert render(view) =~ "Scrape queued for Example Shop."
    end
  end
end
