defmodule InstabotWeb.ProfilesLive do
  @moduledoc false
  use InstabotWeb, :live_view

  alias Instabot.Instagram
  alias Instabot.Instagram.TrackedProfile
  alias Instabot.Notifications
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
          <h1 class="text-2xl font-bold">Tracked Profiles</h1>
          <button phx-click="show_form" class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="size-4" /> Add Profile
          </button>
        </div>

        <Card.render :if={@show_form}>
          <h3 class="text-lg font-semibold mb-4">Add Instagram Profile</h3>
          <.form
            for={@form}
            id="add_profile_form"
            phx-submit="save_profile"
            phx-change="validate_profile"
            class="flex flex-col gap-y-4"
          >
            <.input
              field={@form[:instagram_username]}
              type="text"
              placeholder="Instagram username (without @)"
              required
              phx-mounted={JS.focus()}
            />
            <.input
              field={@form[:display_name]}
              type="text"
              placeholder="Display name (optional)"
            />
            <div class="flex gap-2">
              <.button phx-disable-with="Adding..." class="btn btn-primary flex-1">
                Add Profile
              </.button>
              <button type="button" phx-click="hide_form" class="btn btn-ghost flex-1">
                Cancel
              </button>
            </div>
          </.form>
        </Card.render>

        <Card.render :if={@profiles != []}>
          <div class="overflow-x-auto">
            <table class="table w-full">
              <thead>
                <tr>
                  <th>Profile</th>
                  <th>Status</th>
                  <th>Notifications</th>
                  <th>Last Scraped</th>
                  <th class="text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={profile <- @profiles}>
                  <td>
                    <div class="flex items-center gap-3">
                      <div class={[
                        "avatar",
                        is_nil(profile_avatar_url(profile)) && "avatar-placeholder"
                      ]}>
                        <div class="bg-neutral text-neutral-content w-10 rounded-full">
                          <img
                            :if={profile_avatar_url(profile)}
                            src={profile_avatar_url(profile)}
                            alt={profile.instagram_username}
                          />
                          <span :if={is_nil(profile_avatar_url(profile))}>
                            {String.first(profile.instagram_username) |> String.upcase()}
                          </span>
                        </div>
                      </div>
                      <div>
                        <div class="font-bold">@{profile.instagram_username}</div>
                        <div :if={profile.display_name} class="text-sm opacity-50">
                          {profile.display_name}
                        </div>
                      </div>
                    </div>
                  </td>
                  <td>
                    <div class={[
                      "badge badge-sm",
                      if(profile.is_active, do: "badge-success", else: "badge-ghost")
                    ]}>
                      {if profile.is_active, do: "active", else: "paused"}
                    </div>
                  </td>
                  <td>
                    <.link
                      navigate={~p"/settings/notifications"}
                      id={"profile-notification-link-#{profile.id}"}
                      class="btn btn-ghost btn-xs"
                    >
                      <.icon name="hero-bell" class="size-3" />
                      {profile_notification_summary(@profile_notification_preferences, profile.id)}
                    </.link>
                  </td>
                  <td class="text-sm opacity-70">
                    {format_last_scraped(profile.last_scraped_at)}
                    <div
                      :if={scrape_message(@scrape_states, profile.id)}
                      id={"profile-scrape-state-#{profile.id}"}
                      class={[
                        "mt-1 text-xs font-medium",
                        scrape_state_class(@scrape_states, profile.id)
                      ]}
                    >
                      {scrape_message(@scrape_states, profile.id)}
                    </div>
                  </td>
                  <td class="text-right whitespace-nowrap">
                    <div class="flex gap-1 justify-end">
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
                            "size-3",
                            scrape_active?(@scrape_states, profile.id) && "animate-spin"
                          ]}
                        /> Scrape
                      </button>
                      <button
                        phx-click="toggle_active"
                        phx-value-id={profile.id}
                        class="btn btn-ghost btn-xs"
                      >
                        {if profile.is_active, do: "Pause", else: "Resume"}
                      </button>
                      <button
                        phx-click="delete_profile"
                        phx-value-id={profile.id}
                        data-confirm={"Remove @#{profile.instagram_username} from tracking?"}
                        class="btn btn-ghost btn-xs text-error"
                      >
                        Remove
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </Card.render>

        <Card.render :if={@profiles == [] and not @show_form}>
          <div class="text-center py-8">
            <.icon name="hero-user-group" class="size-12 opacity-30 mx-auto mb-4" />
            <h3 class="text-lg font-semibold mb-2">No profiles yet</h3>
            <p class="text-sm opacity-70 mb-4">
              Add Instagram profiles to monitor their posts and stories.
            </p>
            <button phx-click="show_form" class="btn btn-primary btn-sm">
              <.icon name="hero-plus" class="size-4" /> Add Your First Profile
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

    if connected?(socket) do
      Events.subscribe(user_id)
    end

    profiles = Instagram.list_tracked_profiles_with_notification_preferences(user_id)
    changeset = Instagram.change_tracked_profile(%TrackedProfile{})

    socket =
      socket
      |> assign(:profiles, profiles)
      |> assign_profile_notification_preferences(user_id, profiles)
      |> assign(:show_form, false)
      |> assign(:scrape_states, ScrapingState.list_for_user(user_id))
      |> assign_form(changeset)

    {:ok, socket}
  end

  @impl true
  def handle_event("show_form", _params, socket) do
    {:noreply, assign(socket, :show_form, true)}
  end

  def handle_event("hide_form", _params, socket) do
    changeset = Instagram.change_tracked_profile(%TrackedProfile{})

    socket =
      socket
      |> assign(:show_form, false)
      |> assign_form(changeset)

    {:noreply, socket}
  end

  def handle_event("validate_profile", %{"tracked_profile" => params}, socket) do
    changeset =
      %TrackedProfile{}
      |> Instagram.change_tracked_profile(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save_profile", %{"tracked_profile" => params}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Instagram.create_tracked_profile(user_id, params) do
      {:ok, profile} ->
        profiles = Instagram.list_tracked_profiles_with_notification_preferences(user_id)
        changeset = Instagram.change_tracked_profile(%TrackedProfile{})

        socket =
          socket
          |> assign(:profiles, profiles)
          |> assign_profile_notification_preferences(user_id, profiles)
          |> assign(:show_form, false)
          |> assign_form(changeset)

        {:noreply, handle_profile_created_scrape(socket, profile)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    profile = Instagram.get_tracked_profile_for_user!(user_id, id)
    {:ok, _profile} = Instagram.toggle_active(profile)
    profiles = Instagram.list_tracked_profiles_with_notification_preferences(user_id)
    action = if profile.is_active, do: "paused", else: "resumed"

    socket =
      socket
      |> assign(:profiles, profiles)
      |> assign_profile_notification_preferences(user_id, profiles)
      |> put_flash(:info, "Profile @#{profile.instagram_username} #{action}.")

    {:noreply, socket}
  end

  def handle_event("scrape_now", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    profile = Instagram.get_tracked_profile_for_user!(user_id, id)

    case enqueue_profile_scrape(profile) do
      {:ok, %{conflict?: true}} ->
        {:noreply, put_flash(socket, :info, "Scrape for @#{profile.instagram_username} already queued.")}

      {:ok, _job, event} ->
        socket =
          socket
          |> assign(:scrape_states, put_scrape_state(socket.assigns.scrape_states, event))
          |> put_flash(:info, "Scrape queued for @#{profile.instagram_username}.")

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue scrape.")}
    end
  end

  def handle_event("delete_profile", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    profile = Instagram.get_tracked_profile_for_user!(user_id, id)
    {:ok, _profile} = Instagram.delete_tracked_profile(profile)
    profiles = Instagram.list_tracked_profiles_with_notification_preferences(user_id)

    socket =
      socket
      |> assign(:profiles, profiles)
      |> assign_profile_notification_preferences(user_id, profiles)
      |> put_flash(:info, "Profile @#{profile.instagram_username} removed.")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:scrape_event, event}, socket) do
    user_id = socket.assigns.current_scope.user.id
    profiles = Instagram.list_tracked_profiles_with_notification_preferences(user_id)
    scrape_states = put_scrape_state(socket.assigns.scrape_states, event)

    socket =
      socket
      |> assign(:profiles, profiles)
      |> assign_profile_notification_preferences(user_id, profiles)
      |> assign(:scrape_states, scrape_states)

    {:noreply, socket}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp assign_profile_notification_preferences(socket, user_id, profiles) do
    user_preference = Notifications.get_or_create_preference(user_id)

    preferences =
      Map.new(profiles, fn profile ->
        {profile.id,
         Notifications.resolve_effective_profile_preference(
           user_preference,
           profile.profile_notification_preference
         )}
      end)

    assign(socket, :profile_notification_preferences, preferences)
  end

  defp profile_notification_summary(preferences, profile_id) do
    preferences
    |> Map.fetch!(profile_id)
    |> Map.fetch!(:frequency)
    |> String.capitalize()
  end

  defp handle_profile_created_scrape(socket, profile) do
    case enqueue_profile_scrape(profile) do
      {:ok, %{conflict?: true}} ->
        put_flash(socket, :info, "Profile @#{profile.instagram_username} added successfully.")

      {:ok, _job, event} ->
        socket
        |> assign(:scrape_states, put_scrape_state(socket.assigns.scrape_states, event))
        |> put_flash(:info, "Profile @#{profile.instagram_username} added and scrape queued.")

      {:error, _reason} ->
        put_flash(socket, :error, "Profile @#{profile.instagram_username} added, but the scrape could not be queued.")
    end
  end

  defp enqueue_profile_scrape(profile) do
    case %{tracked_profile_id: profile.id} |> ScrapeProfile.new() |> Oban.insert() do
      {:ok, %{conflict?: true} = job} -> {:ok, job}
      {:ok, job} -> {:ok, job, Events.broadcast(profile, :queued)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp format_last_scraped(nil), do: "Never"

  defp format_last_scraped(datetime) do
    DateTimeFormatter.datetime(datetime)
  end

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
