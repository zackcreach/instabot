defmodule Instabot.Shops.ShopifySite do
  @moduledoc false
  use Instabot.Schema, prefix: "shs"

  import Ecto.Changeset

  alias Instabot.Network.SafeUrl

  @scrape_interval_minutes [30, 60, 360, 720, 1440]

  schema "shopify_sites" do
    field :name, :string
    field :home_url, :string
    field :product_url, :string
    field :is_active, :boolean, default: true
    field :last_scraped_at, :utc_datetime
    field :scrape_interval_minutes, :integer, default: 30

    belongs_to :user, Instabot.Accounts.User, type: UXID
    has_many :snapshots, Instabot.Shops.ShopifySnapshot
    has_many :changes, Instabot.Shops.ShopifyChange

    timestamps(type: :utc_datetime)
  end

  def changeset(site, attrs) do
    site
    |> cast(attrs, [:name, :home_url, :product_url, :is_active, :scrape_interval_minutes])
    |> update_change(:home_url, &normalize_url/1)
    |> update_change(:product_url, &normalize_url/1)
    |> validate_required([:name, :home_url, :user_id, :scrape_interval_minutes])
    |> validate_length(:name, max: 120)
    |> validate_url(:home_url)
    |> validate_product_url()
    |> validate_inclusion(:scrape_interval_minutes, @scrape_interval_minutes)
    |> unique_constraint([:user_id, :home_url], error_key: :home_url)
  end

  def scrape_interval_minutes, do: @scrape_interval_minutes

  defp normalize_url(nil), do: nil
  defp normalize_url(""), do: nil

  defp normalize_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> ensure_scheme()
    |> URI.parse()
    |> URI.to_string()
    |> String.trim_trailing("/")
  end

  defp ensure_scheme(url), do: if(String.match?(url, ~r/^https?:\/\//i), do: url, else: "https://#{url}")

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn ^field, url ->
      case SafeUrl.validate_structure(url) do
        {:ok, _uri} -> []
        {:error, :unsafe_url} -> [{field, "must be a valid URL using port 80 or 443 without credentials"}]
      end
    end)
  end

  defp validate_product_url(changeset) do
    case get_field(changeset, :product_url) do
      nil -> changeset
      _url -> validate_url(changeset, :product_url)
    end
  end
end
