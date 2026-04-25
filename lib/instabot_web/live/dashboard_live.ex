defmodule InstabotWeb.DashboardLive do
  @moduledoc false
  use InstabotWeb, :live_view

  alias Instabot.Instagram
  alias Instabot.Scraping.Events
  alias Instabot.Scraping.State, as: ScrapingState
  alias Instabot.Workers.ScrapeProfile
  alias InstabotWeb.DateTimeFormatter

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
              Last login: {DateTimeFormatter.long_datetime(@connection.last_login_at)}
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
                <div class={[
                  "avatar",
                  is_nil(profile_avatar_url(profile)) && "placeholder"
                ]}>
                  <div class="bg-neutral text-neutral-content w-8 rounded-full">
                    <img
                      :if={profile_avatar_url(profile)}
                      src={profile_avatar_url(profile)}
                      alt={profile.instagram_username}
                    />
                    <span :if={is_nil(profile_avatar_url(profile))} class="text-xs">
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
                  disabled={scrape_active?(@scrape_states, profile.id)}
                  class="btn btn-ghost btn-xs"
                >
                  <.icon
                    name="hero-arrow-path"
                    class={[
                      "size-4",
                      scrape_active?(@scrape_states, profile.id) && "animate-spin"
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
                  {DateTimeFormatter.short_relative(profile.last_scraped_at)}
                </span>
                <span
                  :if={scrape_message(@scrape_states, profile.id)}
                  id={"dashboard-scrape-state-#{profile.id}"}
                  class={[
                    "text-xs font-medium",
                    scrape_state_class(@scrape_states, profile.id)
                  ]}
                >
                  {scrape_message(@scrape_states, profile.id)}
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
      Events.subscribe(user_id)
    end

    socket =
      socket
      |> assign(:scrape_states, ScrapingState.list_for_user(user_id))
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
        event = Events.broadcast(profile, :queued)

        socket =
          socket
          |> assign(:scrape_states, put_scrape_state(socket.assigns.scrape_states, event))
          |> put_flash(:info, "Scrape queued for @#{profile.instagram_username}.")

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue scrape.")}
    end
  end

  def handle_event("scrape_all", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    profiles = Instagram.list_tracked_profiles(user_id)

    {queued_count, scrape_states} =
      profiles
      |> Enum.filter(& &1.is_active)
      |> Enum.reduce({0, socket.assigns.scrape_states}, fn profile, {count, states} ->
        case %{tracked_profile_id: profile.id} |> ScrapeProfile.new() |> Oban.insert() do
          {:ok, %{conflict?: true}} ->
            {count, states}

          {:ok, _job} ->
            event = Events.broadcast(profile, :queued)
            {count + 1, put_scrape_state(states, event)}

          {:error, _} ->
            {count, states}
        end
      end)

    socket =
      socket
      |> assign(:scrape_states, scrape_states)
      |> put_flash(:info, queued_flash(queued_count))

    {:noreply, socket}
  end

  defp queued_flash(0), do: "No scrape jobs queued."
  defp queued_flash(1), do: "1 scrape job queued."
  defp queued_flash(count), do: "#{count} scrape jobs queued."

  @impl true
  def handle_info({:scrape_event, event}, socket) do
    user_id = socket.assigns.current_scope.user.id
    scrape_states = put_scrape_state(socket.assigns.scrape_states, event)

    socket =
      socket
      |> assign(:scrape_states, scrape_states)
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

  defp put_scrape_state(scrape_states, %{profile_id: profile_id} = event) do
    Map.put(scrape_states, profile_id, event)
  end

  defp scrape_active?(scrape_states, profile_id) do
    scrape_states
    |> Map.get(profile_id, %{})
    |> Map.get(:status)
    |> Events.active?()
  end

  defp scrape_message(scrape_states, profile_id) do
    scrape_states
    |> Map.get(profile_id, %{})
    |> Map.get(:message)
  end

  defp scrape_state_class(scrape_states, profile_id) do
    case scrape_states |> Map.get(profile_id, %{}) |> Map.get(:status) do
      :failed -> "text-error"
      :cancelled -> "text-warning"
      :completed -> "text-success"
      _status -> "text-info"
    end
  end

  defp profile_avatar_url(%{profile_pic_url: url}) when is_binary(url) and url != "", do: Instabot.Media.to_url(url)
  defp profile_avatar_url(_profile), do: nil
end
