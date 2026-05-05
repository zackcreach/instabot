defmodule Instabot.Workers.ScrapeShopifySite do
  @moduledoc """
  Scrapes one tracked Shopify site and records any detected changes.
  """

  use Oban.Worker,
    queue: :scraping,
    max_attempts: 2,
    unique: [period: 300, keys: [:shopify_site_id]]

  alias Instabot.Shops
  alias Instabot.Shops.Scraper

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"shopify_site_id" => shopify_site_id}}) do
    site = Shops.get_site!(shopify_site_id)

    with :ok <- verify_active(site),
         {:ok, {_snapshot, changes}} <- Scraper.scrape_and_persist(site) do
      Logger.info("Scraped Shopify site #{site.name} with #{length(changes)} changes")
      :ok
    end
  end

  defp verify_active(%{is_active: true}), do: :ok
  defp verify_active(_site), do: {:cancel, "Shopify site is inactive"}
end
