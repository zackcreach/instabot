defmodule Instabot.Shops.Scraper do
  @moduledoc """
  Captures Shopify homepage screenshots, banner signals, and product price data.
  """

  alias Instabot.Media
  alias Instabot.Scraper.Browser
  alias Instabot.Scraper.Supervisor, as: ScraperSupervisor
  alias Instabot.Shops
  alias Instabot.Shops.ChangeDetector
  alias Instabot.Shops.ProductData
  alias Instabot.Shops.ShopifySite

  @viewport %{width: 1440, height: 1200}
  @top_banner_js """
  (() => {
    const elements = Array.from(document.querySelectorAll("header, [role='banner'], announcement-bar, .announcement-bar, .top-bar, .promo-bar, .site-header, body *"));
    const visibleText = elements
      .filter(element => {
        const rect = element.getBoundingClientRect();
        const styles = window.getComputedStyle(element);
        return rect.top >= 0 && rect.top < 220 && rect.width > 0 && rect.height > 0 && styles.visibility !== "hidden" && styles.display !== "none";
      })
      .map(element => element.innerText || element.textContent || "")
      .join(" ")
      .replace(/\\s+/g, " ")
      .trim();

    return visibleText.slice(0, 1000);
  })()
  """

  def scrape_and_persist(%ShopifySite{} = site) do
    with {:ok, attrs} <- scrape(site) do
      Shops.create_snapshot_with_changes(site, attrs)
    end
  end

  def scrape(%ShopifySite{} = site) do
    with {:ok, browser} <- ScraperSupervisor.start_browser() do
      try do
        scrape_with_browser(browser, site)
      after
        Browser.stop(browser)
      end
    end
  end

  defp scrape_with_browser(browser, site) do
    with {:ok, _launch} <- Browser.launch(browser, []),
         {:ok, page_id} <- Browser.new_page(browser, viewport: @viewport),
         {:ok, _navigation} <-
           Browser.navigate(browser, page_id, site.home_url, wait_until: "networkidle", timeout: 45_000),
         {:ok, banner_text} <- Browser.evaluate(browser, page_id, @top_banner_js),
         {:ok, %{"base64" => base64}} <- Browser.screenshot(browser, page_id, full_page: true),
         {:ok, screenshot_attrs} <- upload_screenshot(site, base64),
         {:ok, product_attrs} <- product_attrs(site.product_url) do
      {:ok,
       screenshot_attrs
       |> Map.merge(%{
         banner_text: banner_text,
         banner_sale_detected: ChangeDetector.sale_banner?(banner_text),
         captured_at: DateTime.utc_now(:second)
       })
       |> Map.merge(product_attrs)}
    end
  end

  defp upload_screenshot(site, base64) do
    with {:ok, bytes} <- Base.decode64(base64) do
      sha256 = :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
      filename = "#{site.id}-#{System.system_time(:second)}.png"

      bytes
      |> Media.upload_image(Path.join("shopify", site.id), filename,
        content_type: "image/png",
        public_id: Path.join(["shopify", site.id, Path.rootname(filename)])
      )
      |> normalize_upload(sha256)
    end
  end

  defp product_attrs(nil), do: {:ok, %{}}
  defp product_attrs(""), do: {:ok, %{}}
  defp product_attrs(product_url), do: ProductData.fetch(product_url)

  defp normalize_upload({:ok, upload}, sha256) do
    {:ok,
     %{
       screenshot_url: upload[:cloudinary_secure_url],
       screenshot_path: upload[:local_path],
       screenshot_sha256: sha256,
       screenshot_cloudinary_public_id: upload[:cloudinary_public_id],
       screenshot_cloudinary_version: upload[:cloudinary_version],
       screenshot_cloudinary_format: upload[:cloudinary_format],
       screenshot_width: upload[:width],
       screenshot_height: upload[:height]
     }}
  end

  defp normalize_upload({:error, reason}, _sha256), do: {:error, reason}
end
