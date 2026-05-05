defmodule Instabot.Shops do
  @moduledoc """
  Shopify monitoring context for tracked sites, snapshots, and changes.
  """

  import Ecto.Query

  alias Instabot.Repo
  alias Instabot.Shops.ChangeDetector
  alias Instabot.Shops.ShopifyChange
  alias Instabot.Shops.ShopifySite
  alias Instabot.Shops.ShopifySnapshot

  def list_sites(user_id) do
    ShopifySite
    |> where(user_id: ^user_id)
    |> order_by(asc: :name)
    |> preload([:snapshots, :changes])
    |> Repo.all()
  end

  def list_sites_with_latest(user_id) do
    user_id
    |> list_sites()
    |> Enum.map(&preload_latest/1)
  end

  def get_site!(id), do: Repo.get!(ShopifySite, id)

  def get_site_for_user!(user_id, id) do
    ShopifySite
    |> where(user_id: ^user_id, id: ^id)
    |> Repo.one!()
  end

  def create_site(user_id, attrs) do
    %ShopifySite{user_id: user_id}
    |> ShopifySite.changeset(attrs)
    |> Repo.insert()
  end

  def change_site(%ShopifySite{} = site, attrs \\ %{}) do
    ShopifySite.changeset(site, attrs)
  end

  def update_site_scrape_interval(%ShopifySite{} = site, attrs) do
    site
    |> ShopifySite.changeset(attrs)
    |> Repo.update()
  end

  def toggle_active(%ShopifySite{} = site) do
    site
    |> Ecto.Changeset.change(%{is_active: not site.is_active})
    |> Repo.update()
  end

  def delete_site(%ShopifySite{} = site), do: Repo.delete(site)

  def list_due_active_sites(now \\ DateTime.utc_now(:second)) do
    ShopifySite
    |> where(is_active: true)
    |> where(
      [site],
      is_nil(site.last_scraped_at) or
        site.last_scraped_at <=
          fragment("? - (? * interval '1 minute')", type(^now, :utc_datetime), site.scrape_interval_minutes)
    )
    |> preload(:user)
    |> Repo.all()
  end

  def scrape_interval_options do
    Enum.map(ShopifySite.scrape_interval_minutes(), fn minutes ->
      {scrape_interval_label(minutes), minutes}
    end)
  end

  def update_last_scraped(%ShopifySite{} = site) do
    site
    |> Ecto.Changeset.change(%{last_scraped_at: DateTime.utc_now(:second)})
    |> Repo.update()
  end

  def latest_snapshot(%ShopifySite{} = site) do
    ShopifySnapshot
    |> where(shopify_site_id: ^site.id)
    |> order_by(desc: :captured_at, desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def list_recent_changes(%ShopifySite{} = site, limit \\ 10) do
    ShopifyChange
    |> where(shopify_site_id: ^site.id)
    |> order_by(desc: :detected_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def create_snapshot_with_changes(%ShopifySite{} = site, attrs) do
    previous_snapshot = latest_snapshot(site)

    fn ->
      snapshot =
        %ShopifySnapshot{shopify_site_id: site.id}
        |> ShopifySnapshot.changeset(attrs)
        |> Repo.insert!()

      changes =
        previous_snapshot
        |> ChangeDetector.detect(snapshot)
        |> Enum.map(&create_change!(site, previous_snapshot, snapshot, &1))

      update_last_scraped(site)
      {snapshot, changes}
    end
    |> Repo.transaction()
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_change!(site, previous_snapshot, snapshot, attrs) do
    %ShopifyChange{
      shopify_site_id: site.id,
      snapshot_id: snapshot.id,
      previous_snapshot_id: previous_snapshot_id(previous_snapshot)
    }
    |> ShopifyChange.changeset(Map.put(attrs, :detected_at, snapshot.captured_at))
    |> Repo.insert!()
  end

  defp previous_snapshot_id(nil), do: nil
  defp previous_snapshot_id(snapshot), do: snapshot.id

  defp preload_latest(site) do
    site
    |> Map.put(:latest_snapshot, latest_snapshot(site))
    |> Map.put(:recent_changes, list_recent_changes(site, 5))
  end

  defp scrape_interval_label(30), do: "30 minutes"
  defp scrape_interval_label(60), do: "1 hour"
  defp scrape_interval_label(360), do: "6 hours"
  defp scrape_interval_label(720), do: "12 hours"
  defp scrape_interval_label(1440), do: "24 hours"
end
