defmodule Instabot.Workers.ScheduleShopifyScrapes do
  @moduledoc """
  Cron-triggered worker that fans out Shopify scrape jobs for due active sites.
  """

  use Oban.Worker, queue: :scraping, max_attempts: 1

  alias Instabot.Shops
  alias Instabot.Workers.ScrapeShopifySite

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    sites = Shops.list_due_active_sites()

    Logger.info("ScheduleShopifyScrapes: enqueueing #{length(sites)} Shopify scrape jobs")

    Enum.each(sites, fn site ->
      case %{shopify_site_id: site.id} |> ScrapeShopifySite.new() |> Oban.insert() do
        {:ok, _job} -> :ok
        {:error, reason} -> Logger.warning("Failed to queue Shopify site #{site.name}: #{inspect(reason)}")
      end
    end)

    :ok
  end
end
