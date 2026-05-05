defmodule Instabot.Workers.ScheduleShopifyScrapesTest do
  use Instabot.DataCase, async: true
  use Oban.Testing, repo: Instabot.Repo

  import Instabot.AccountsFixtures
  import Instabot.ShopsFixtures

  alias Instabot.Workers.ScheduleShopifyScrapes
  alias Instabot.Workers.ScrapeShopifySite

  test "enqueues due Shopify site scrapes" do
    user = user_fixture()
    site = shopify_site_fixture(user)

    assert :ok == perform_job(ScheduleShopifyScrapes, %{})

    assert_enqueued(worker: ScrapeShopifySite, args: %{shopify_site_id: site.id})
  end
end
