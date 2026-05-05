defmodule InstabotWeb.ShopsLive do
  @moduledoc false
  use InstabotWeb, :live_view

  alias Instabot.Shops
  alias Instabot.Shops.ShopifySite
  alias Instabot.Workers.ScrapeShopifySite
  alias InstabotWeb.DateTimeFormatter

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} container_class="max-w-7xl">
      <div class="space-y-6">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 class="text-2xl font-bold">Shopify Monitors</h1>
            <p class="text-sm opacity-70">
              Track sale banners, homepage screenshot changes, and product price movement.
            </p>
          </div>
          <button id="show-shopify-site-form" phx-click="show_form" class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="size-4" /> Add Site
          </button>
        </div>

        <Card.render :if={@show_form}>
          <h3 class="mb-4 text-lg font-semibold">Add Shopify Site</h3>
          <.form
            for={@form}
            id="add-shopify-site-form"
            phx-submit="save_site"
            phx-change="validate_site"
            class="grid gap-4 lg:grid-cols-2"
          >
            <.input field={@form[:name]} type="text" label="Name" required phx-mounted={JS.focus()} />
            <.input field={@form[:home_url]} type="url" label="Homepage URL" required />
            <.input field={@form[:product_url]} type="url" label="Product URL" />
            <.input
              field={@form[:scrape_interval_minutes]}
              type="select"
              label="Scrape every"
              options={@scrape_interval_options}
            />
            <div class="flex gap-2 lg:col-span-2">
              <.button phx-disable-with="Adding..." class="btn btn-primary flex-1">
                Add Site
              </.button>
              <button type="button" phx-click="hide_form" class="btn btn-ghost flex-1">
                Cancel
              </button>
            </div>
          </.form>
        </Card.render>

        <div :if={@sites != []} id="shopify-sites" class="grid gap-4 xl:grid-cols-2">
          <div
            :for={site <- @sites}
            id={"shopify-site-#{site.id}"}
            class="rounded-lg border border-base-300 bg-base-100 p-5 shadow-sm"
          >
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0">
                <div class="flex flex-wrap items-center gap-2">
                  <h2 class="truncate text-lg font-semibold">{site.name}</h2>
                  <span class={[
                    "badge badge-sm",
                    if(site.is_active, do: "badge-success", else: "badge-ghost")
                  ]}>
                    {if site.is_active, do: "active", else: "paused"}
                  </span>
                </div>
                <a
                  href={site.home_url}
                  target="_blank"
                  class="link link-hover break-all text-sm opacity-70"
                >
                  {site.home_url}
                </a>
              </div>
              <div class="flex shrink-0 gap-1">
                <button
                  :if={site.is_active}
                  phx-click="scrape_now"
                  phx-value-id={site.id}
                  class="btn btn-ghost btn-xs"
                >
                  <.icon name="hero-arrow-path" class="size-3" /> Scrape
                </button>
                <button phx-click="toggle_active" phx-value-id={site.id} class="btn btn-ghost btn-xs">
                  {if site.is_active, do: "Pause", else: "Resume"}
                </button>
                <button
                  phx-click="delete_site"
                  phx-value-id={site.id}
                  data-confirm={"Remove #{site.name} from Shopify monitoring?"}
                  class="btn btn-ghost btn-xs text-error"
                >
                  Remove
                </button>
              </div>
            </div>

            <div class="mt-4 grid gap-4 md:grid-cols-[180px_1fr]">
              <div class="overflow-hidden rounded-md border border-base-300 bg-base-200">
                <img
                  :if={snapshot_image_url(site.latest_snapshot)}
                  src={snapshot_image_url(site.latest_snapshot)}
                  alt={"Latest screenshot for #{site.name}"}
                  class="h-48 w-full object-cover object-top"
                />
                <div
                  :if={is_nil(snapshot_image_url(site.latest_snapshot))}
                  class="flex h-48 items-center justify-center text-sm opacity-60"
                >
                  No screenshot
                </div>
              </div>

              <div class="space-y-3">
                <dl class="grid grid-cols-2 gap-3 text-sm">
                  <div>
                    <dt class="opacity-60">Last scraped</dt>
                    <dd class="font-medium">{format_datetime(site.last_scraped_at)}</dd>
                  </div>
                  <div>
                    <dt class="opacity-60">Scrape every</dt>
                    <dd>
                      <.form
                        for={%{}}
                        as={:shopify_site}
                        id={"shopify-site-interval-form-#{site.id}"}
                        phx-change="update_scrape_interval"
                        phx-value-id={site.id}
                      >
                        <.input
                          id={"shopify-site-interval-#{site.id}"}
                          name="shopify_site[scrape_interval_minutes]"
                          type="select"
                          value={site.scrape_interval_minutes}
                          options={@scrape_interval_options}
                          class="select select-xs w-32"
                        />
                      </.form>
                    </dd>
                  </div>
                  <div>
                    <dt class="opacity-60">Sale banner</dt>
                    <dd class={
                      if sale_banner?(site.latest_snapshot),
                        do: "font-medium text-success",
                        else: "font-medium"
                    }>
                      {sale_banner_label(site.latest_snapshot)}
                    </dd>
                  </div>
                  <div>
                    <dt class="opacity-60">Product price</dt>
                    <dd class="font-medium">{product_price(site.latest_snapshot)}</dd>
                  </div>
                </dl>

                <div :if={site.product_url} class="text-sm">
                  <span class="opacity-60">Product:</span>
                  <a href={site.product_url} target="_blank" class="link link-hover break-all">
                    {site.product_url}
                  </a>
                </div>

                <div
                  :if={site.latest_snapshot && site.latest_snapshot.banner_text}
                  class="rounded-md bg-base-200 p-3 text-sm"
                >
                  {site.latest_snapshot.banner_text}
                </div>
              </div>
            </div>

            <div class="mt-4 border-t border-base-200 pt-4">
              <h3 class="mb-2 text-sm font-semibold">Recent Changes</h3>
              <div :if={site.recent_changes == []} class="text-sm opacity-60">
                No changes recorded yet.
              </div>
              <ul :if={site.recent_changes != []} class="space-y-2">
                <li
                  :for={change <- site.recent_changes}
                  id={"shopify-change-#{change.id}"}
                  class="text-sm"
                >
                  <div class="font-medium">{change.summary}</div>
                  <div class="opacity-60">{format_datetime(change.detected_at)}</div>
                </li>
              </ul>
            </div>
          </div>
        </div>

        <Card.render :if={@sites == [] and not @show_form}>
          <div class="py-8 text-center">
            <.icon name="hero-shopping-bag" class="mx-auto mb-4 size-12 opacity-30" />
            <h3 class="mb-2 text-lg font-semibold">No Shopify monitors yet</h3>
            <p class="mb-4 text-sm opacity-70">
              Add a Shopify homepage and optional product URL to watch sale messaging and prices.
            </p>
            <button
              id="show-first-shopify-site-form"
              phx-click="show_form"
              class="btn btn-primary btn-sm"
            >
              <.icon name="hero-plus" class="size-4" /> Add Your First Site
            </button>
          </div>
        </Card.render>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    changeset = Shops.change_site(%ShopifySite{})

    socket =
      socket
      |> assign(:sites, Shops.list_sites_with_latest(user_id))
      |> assign(:show_form, false)
      |> assign(:scrape_interval_options, Shops.scrape_interval_options())
      |> assign_form(changeset)

    {:ok, socket}
  end

  @impl true
  def handle_event("show_form", _params, socket) do
    {:noreply, assign(socket, :show_form, true)}
  end

  def handle_event("hide_form", _params, socket) do
    changeset = Shops.change_site(%ShopifySite{})

    socket =
      socket
      |> assign(:show_form, false)
      |> assign_form(changeset)

    {:noreply, socket}
  end

  def handle_event("validate_site", %{"shopify_site" => params}, socket) do
    changeset =
      %ShopifySite{}
      |> Shops.change_site(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save_site", %{"shopify_site" => params}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Shops.create_site(user_id, params) do
      {:ok, site} ->
        socket =
          socket
          |> refresh_sites(user_id)
          |> assign(:show_form, false)
          |> assign_form(Shops.change_site(%ShopifySite{}))

        {:noreply, handle_site_created_scrape(socket, site)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("scrape_now", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    site = Shops.get_site_for_user!(user_id, id)

    case enqueue_scrape(site) do
      {:ok, %{conflict?: true}} ->
        {:noreply, put_flash(socket, :info, "Scrape for #{site.name} already queued.")}

      {:ok, _job} ->
        {:noreply, put_flash(socket, :info, "Scrape queued for #{site.name}.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue scrape.")}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    site = Shops.get_site_for_user!(user_id, id)
    {:ok, _site} = Shops.toggle_active(site)
    action = if site.is_active, do: "paused", else: "resumed"

    socket =
      socket
      |> refresh_sites(user_id)
      |> put_flash(:info, "#{site.name} #{action}.")

    {:noreply, socket}
  end

  def handle_event("update_scrape_interval", %{"id" => id, "shopify_site" => params}, socket) do
    user_id = socket.assigns.current_scope.user.id
    site = Shops.get_site_for_user!(user_id, id)

    case Shops.update_site_scrape_interval(site, params) do
      {:ok, site} ->
        socket =
          socket
          |> refresh_sites(user_id)
          |> put_flash(:info, "Scrape interval updated for #{site.name}.")

        {:noreply, socket}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Choose a supported scrape interval.")}
    end
  end

  def handle_event("delete_site", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    site = Shops.get_site_for_user!(user_id, id)
    {:ok, _site} = Shops.delete_site(site)

    socket =
      socket
      |> refresh_sites(user_id)
      |> put_flash(:info, "#{site.name} removed.")

    {:noreply, socket}
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  defp refresh_sites(socket, user_id) do
    assign(socket, :sites, Shops.list_sites_with_latest(user_id))
  end

  defp handle_site_created_scrape(socket, site) do
    case enqueue_scrape(site) do
      {:ok, %{conflict?: true}} ->
        put_flash(socket, :info, "#{site.name} added successfully.")

      {:ok, _job} ->
        put_flash(socket, :info, "#{site.name} added and scrape queued.")

      {:error, _reason} ->
        put_flash(socket, :error, "#{site.name} added, but the scrape could not be queued.")
    end
  end

  defp enqueue_scrape(site) do
    site.id
    |> then(&%{shopify_site_id: &1})
    |> ScrapeShopifySite.new()
    |> Oban.insert()
  end

  defp snapshot_image_url(nil), do: nil
  defp snapshot_image_url(%{screenshot_url: url}) when is_binary(url) and url != "", do: url
  defp snapshot_image_url(%{screenshot_path: path}) when is_binary(path) and path != "", do: Instabot.Media.to_url(path)
  defp snapshot_image_url(_snapshot), do: nil

  defp sale_banner?(%{banner_sale_detected: true}), do: true
  defp sale_banner?(_snapshot), do: false

  defp sale_banner_label(%{banner_sale_detected: true}), do: "Detected"
  defp sale_banner_label(%{banner_sale_detected: false}), do: "No sale signal"
  defp sale_banner_label(_snapshot), do: "Unknown"

  defp product_price(%{product_price_cents: cents, product_currency: currency}) when is_integer(cents) do
    currency = currency || "USD"
    "#{currency} #{:erlang.float_to_binary(cents / 100, decimals: 2)}"
  end

  defp product_price(_snapshot), do: "Not tracked"

  defp format_datetime(nil), do: "Never"
  defp format_datetime(datetime), do: DateTimeFormatter.datetime(datetime)
end
