defmodule InstabotWeb.DashboardLive do
  @moduledoc false
  use InstabotWeb, :live_view

  alias Instabot.Instagram
  alias Instabot.Workers.ScrapeProfile

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Dashboard</h1>
          <div class="flex gap-2">
            <button
              :if={Enum.any?(@profiles, & &1.is_active)}
              phx-click="scrape_all"
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Scrape All
            </button>
            <.link navigate={~p"/profiles"} class="btn btn-primary btn-sm">
              Manage Profiles
            </.link>
          </div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div class="stat bg-base-100 shadow rounded-lg">
            <div class="stat-title">Tracked Profiles</div>
            <div class="stat-value">{@profile_count}</div>
          </div>
          <div class="stat bg-base-100 shadow rounded-lg">
            <div class="stat-title">Posts Collected</div>
            <div class="stat-value">{@post_count}</div>
          </div>
          <div class="stat bg-base-100 shadow rounded-lg">
            <div class="stat-title">Stories Collected</div>
            <div class="stat-value">{@story_count}</div>
          </div>
        </div>

        <Card.render>
          <h3 class="text-lg font-semibold mb-4">Instagram Connection</h3>
          <%= if @connection do %>
            <div class="flex items-center gap-3">
              <div class={"badge " <> connection_badge_class(@connection.status)}>
                {@connection.status}
              </div>
              <span class="text-sm">@{@connection.instagram_username}</span>
            </div>
            <p :if={@connection.last_login_at} class="text-sm opacity-70 mt-2">
              Last login: {Calendar.strftime(@connection.last_login_at, "%b %d, %Y at %I:%M %p")}
            </p>
          <% else %>
            <p class="text-sm opacity-70 mb-4">
              Connect your Instagram account to start scraping posts and stories.
            </p>
            <.link navigate={~p"/connect"} class="btn btn-primary btn-sm">
              Connect Instagram
            </.link>
          <% end %>
        </Card.render>

        <Card.render :if={@profiles != []}>
          <h3 class="text-lg font-semibold mb-4">Tracked Profiles</h3>
          <div class="space-y-3">
            <div
              :for={profile <- @profiles}
              class="flex items-center justify-between py-2 border-b border-base-200 last:border-0"
            >
              <div class="flex items-center gap-3">
                <div class="avatar placeholder">
                  <div class="bg-neutral text-neutral-content w-8 rounded-full">
                    <span class="text-xs">
                      {String.first(profile.instagram_username) |> String.upcase()}
                    </span>
                  </div>
                </div>
                <div>
                  <span class="font-medium">@{profile.instagram_username}</span>
                  <span :if={profile.display_name} class="text-sm opacity-70 ml-2">
                    {profile.display_name}
                  </span>
                </div>
              </div>
              <div class="flex items-center gap-2">
                <button
                  :if={profile.is_active}
                  phx-click="scrape_now"
                  phx-value-id={profile.id}
                  disabled={MapSet.member?(@scraping_profile_ids, profile.id)}
                  class="btn btn-ghost btn-xs"
                >
                  <.icon
                    name="hero-arrow-path"
                    class={[
                      "size-4",
                      MapSet.member?(@scraping_profile_ids, profile.id) && "animate-spin"
                    ]}
                  /> Scrape
                </button>
                <div class={[
                  "badge badge-sm",
                  if(profile.is_active, do: "badge-success", else: "badge-ghost")
                ]}>
                  {if profile.is_active, do: "active", else: "paused"}
                </div>
                <span :if={profile.last_scraped_at} class="text-xs opacity-50">
                  {relative_time(profile.last_scraped_at)}
                </span>
              </div>
            </div>
          </div>
        </Card.render>

        <Card.render :if={@profiles == []}>
          <div class="text-center py-8">
            <.icon name="hero-camera" class="size-12 opacity-30 mx-auto mb-4" />
            <h3 class="text-lg font-semibold mb-2">No profiles tracked yet</h3>
            <p class="text-sm opacity-70 mb-4">
              Add Instagram profiles to start collecting posts and stories.
            </p>
            <.link navigate={~p"/profiles"} class="btn btn-primary btn-sm">
              Add Profiles
            </.link>
          </div>
        </Card.render>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Instabot.PubSub, "scrape_updates:#{user_id}")
    end

    socket =
      socket
      |> assign(:scraping_profile_ids, MapSet.new())
      |> load_data(user_id)

    {:ok, socket}
  end

  @impl true
  def handle_event("scrape_now", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    profile = Instagram.get_tracked_profile_for_user!(user_id, id)

    case %{tracked_profile_id: profile.id} |> ScrapeProfile.new() |> Oban.insert() do
      {:ok, %{conflict?: true}} ->
        {:noreply, put_flash(socket, :info, "Scrape for @#{profile.instagram_username} already queued.")}

      {:ok, _job} ->
        scraping_ids = MapSet.put(socket.assigns.scraping_profile_ids, profile.id)

        socket =
          socket
          |> assign(:scraping_profile_ids, scraping_ids)
          |> put_flash(:info, "Scrape queued for @#{profile.instagram_username}.")

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue scrape.")}
    end
  end

  def handle_event("scrape_all", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    profiles = Instagram.list_tracked_profiles(user_id)

    {queued_count, scraping_ids} =
      profiles
      |> Enum.filter(& &1.is_active)
      |> Enum.reduce({0, socket.assigns.scraping_profile_ids}, fn profile, {count, ids} ->
        case %{tracked_profile_id: profile.id} |> ScrapeProfile.new() |> Oban.insert() do
          {:ok, %{conflict?: true}} -> {count, ids}
          {:ok, _job} -> {count + 1, MapSet.put(ids, profile.id)}
          {:error, _} -> {count, ids}
        end
      end)

    socket =
      socket
      |> assign(:scraping_profile_ids, scraping_ids)
      |> put_flash(:info, queued_flash(queued_count))

    {:noreply, socket}
  end

  defp queued_flash(0), do: "No scrape jobs queued."
  defp queued_flash(1), do: "1 scrape job queued."
  defp queued_flash(count), do: "#{count} scrape jobs queued."

  @impl true
  def handle_info({:scrape_completed, profile_id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    scraping_ids = MapSet.delete(socket.assigns.scraping_profile_ids, profile_id)

    socket =
      socket
      |> assign(:scraping_profile_ids, scraping_ids)
      |> load_data(user_id)

    {:noreply, socket}
  end

  defp load_data(socket, user_id) do
    socket
    |> assign(:profile_count, Instagram.count_tracked_profiles(user_id))
    |> assign(:post_count, Instagram.count_posts(user_id))
    |> assign(:story_count, Instagram.count_stories(user_id))
    |> assign(:profiles, Instagram.list_tracked_profiles(user_id))
    |> assign(:connection, Instagram.get_connection_for_user(user_id))
  end

  defp connection_badge_class("connected"), do: "badge-success"
  defp connection_badge_class("connecting"), do: "badge-warning"
  defp connection_badge_class("expired"), do: "badge-error"
  defp connection_badge_class(_), do: "badge-ghost"

  defp relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
end
