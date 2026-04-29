defmodule InstabotWeb.NotificationSettingsLive do
  @moduledoc false
  use InstabotWeb, :live_view

  alias Instabot.Instagram
  alias Instabot.Notifications
  alias Phoenix.HTML.Form

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto w-full max-w-5xl space-y-6">
        <Card.render>
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold">Notification Settings</h3>
            <.link navigate={~p"/users/settings"} class="btn btn-ghost btn-xs">
              ← Account Settings
            </.link>
          </div>
          <p class="text-sm opacity-70 mb-6">
            Configure how and when you receive email digests of new posts and stories.
          </p>

          <.form
            for={@form}
            id="notification_form"
            phx-submit="save"
            phx-change="validate"
            class="flex flex-col gap-y-4"
          >
            <.input
              field={@form[:frequency]}
              type="select"
              label="Email Frequency"
              options={[
                {"Disabled", "disabled"},
                {"Immediate (after each scrape)", "immediate"},
                {"Daily digest", "daily"},
                {"Weekly digest", "weekly"}
              ]}
            />

            <div :if={show_daily_options?(@form)} class="pl-4 border-l-2 border-primary space-y-4">
              <.input
                field={@form[:daily_send_at]}
                type="time"
                label="Send daily digest at"
              />
            </div>

            <div :if={show_weekly_options?(@form)} class="pl-4 border-l-2 border-primary space-y-4">
              <.input
                field={@form[:daily_send_at]}
                type="time"
                label="Send weekly digest at"
              />
              <.input
                field={@form[:weekly_send_day]}
                type="select"
                label="Day of week"
                options={[
                  {"Monday", "1"},
                  {"Tuesday", "2"},
                  {"Wednesday", "3"},
                  {"Thursday", "4"},
                  {"Friday", "5"},
                  {"Saturday", "6"},
                  {"Sunday", "7"}
                ]}
              />
            </div>

            <.input
              field={@form[:email_address]}
              type="email"
              label="Send to (leave blank for account email)"
              placeholder={@current_email}
            />

            <div class="divider">Content</div>

            <.input
              field={@form[:include_images]}
              type="checkbox"
              label="Include images in email"
            />
            <.input
              field={@form[:include_ocr]}
              type="checkbox"
              label="Include OCR text from stories"
            />

            <.button phx-disable-with="Saving..." class="btn btn-primary w-full">
              Save Preferences
            </.button>
          </.form>
        </Card.render>

        <Card.render :if={@profiles != []}>
          <div class="mb-4 flex items-center justify-between gap-4">
            <div>
              <h3 class="text-lg font-semibold">Profile Overrides</h3>
              <p class="text-sm opacity-70">
                Override the defaults for individual tracked profiles.
              </p>
            </div>
            <.link navigate={~p"/profiles"} class="btn btn-ghost btn-sm">
              Manage Profiles
            </.link>
          </div>

          <div class="overflow-x-auto">
            <table id="profile_notification_preferences" class="table w-full">
              <thead>
                <tr>
                  <th>Profile</th>
                  <th>Frequency</th>
                  <th>Images</th>
                  <th>OCR</th>
                  <th>Effective</th>
                  <th class="text-right">Action</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={profile <- @profiles} id={"profile-notification-row-#{profile.id}"}>
                  <td>
                    <div class="font-semibold">@{profile.instagram_username}</div>
                    <div :if={profile.display_name} class="text-xs opacity-60">
                      {profile.display_name}
                    </div>
                  </td>
                  <td colspan="5">
                    <.form
                      for={profile_form(@profile_forms, profile.id)}
                      id={"profile-notification-form-#{profile.id}"}
                      phx-submit="save_profile_preference"
                      phx-value-id={profile.id}
                      class="grid min-w-[720px] grid-cols-[1fr_1fr_1fr_1.2fr_auto] items-end gap-3"
                    >
                      <.input
                        field={profile_form(@profile_forms, profile.id)[:frequency]}
                        type="select"
                        label="Frequency"
                        options={[
                          {"Inherit", "inherit"},
                          {"Immediate", "immediate"},
                          {"Daily", "daily"},
                          {"Weekly", "weekly"},
                          {"Disabled", "disabled"}
                        ]}
                      />
                      <.input
                        field={profile_form(@profile_forms, profile.id)[:include_images]}
                        type="select"
                        label="Images"
                        value={
                          override_value(profile.profile_notification_preference, :include_images)
                        }
                        options={[
                          {"Inherit", "inherit"},
                          {"Include", "true"},
                          {"Exclude", "false"}
                        ]}
                      />
                      <.input
                        field={profile_form(@profile_forms, profile.id)[:include_ocr]}
                        type="select"
                        label="OCR"
                        value={override_value(profile.profile_notification_preference, :include_ocr)}
                        options={[
                          {"Inherit", "inherit"},
                          {"Include", "true"},
                          {"Exclude", "false"}
                        ]}
                      />
                      <div class="pb-2 text-sm">
                        {effective_summary(@effective_preferences, profile.id)}
                      </div>
                      <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm mb-2">
                        Save
                      </.button>
                    </.form>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </Card.render>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    preference = Notifications.get_or_create_preference(user.id)
    changeset = Notifications.change_preference(preference)
    profiles = load_profiles(user.id)

    socket =
      socket
      |> assign(:preference, preference)
      |> assign(:current_email, user.email)
      |> assign_profile_preferences(user.id, profiles)
      |> assign_form(changeset)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"notification_preference" => params}, socket) do
    changeset =
      socket.assigns.preference
      |> Notifications.change_preference(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"notification_preference" => params}, socket) do
    case Notifications.update_preference(socket.assigns.preference, params) do
      {:ok, preference} ->
        changeset = Notifications.change_preference(preference)
        profiles = load_profiles(socket.assigns.current_scope.user.id)

        socket =
          socket
          |> assign(:preference, preference)
          |> assign_profile_preferences(socket.assigns.current_scope.user.id, profiles)
          |> assign_form(changeset)
          |> put_flash(:info, "Notification preferences saved.")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("save_profile_preference", %{"id" => id, "profile_notification_preference" => params}, socket) do
    user_id = socket.assigns.current_scope.user.id
    profile = Instagram.get_tracked_profile_for_user!(user_id, id)
    preference = Notifications.get_or_create_profile_preference(user_id, profile.id)

    case Notifications.update_profile_preference(preference, normalize_profile_preference_params(params)) do
      {:ok, _preference} ->
        profiles = load_profiles(user_id)

        socket =
          socket
          |> assign_profile_preferences(user_id, profiles)
          |> put_flash(:info, "Profile notification preference saved.")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_profile_form(socket, profile.id, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp assign_profile_preferences(socket, user_id, profiles) do
    Enum.each(profiles, fn profile ->
      Notifications.get_or_create_profile_preference(user_id, profile.id)
    end)

    profiles = load_profiles(user_id)

    profile_forms =
      Map.new(profiles, fn profile ->
        preference = profile.profile_notification_preference
        {profile.id, to_form(Notifications.change_profile_preference(preference))}
      end)

    effective_preferences =
      Map.new(profiles, fn profile ->
        {profile.id, Notifications.effective_profile_preference(user_id, profile.id)}
      end)

    socket
    |> assign(:profiles, profiles)
    |> assign(:profile_forms, profile_forms)
    |> assign(:effective_preferences, effective_preferences)
  end

  defp assign_profile_form(socket, profile_id, %Ecto.Changeset{} = changeset) do
    profile_forms = Map.put(socket.assigns.profile_forms, profile_id, to_form(changeset))
    assign(socket, :profile_forms, profile_forms)
  end

  defp load_profiles(user_id) do
    Instagram.list_tracked_profiles_with_notification_preferences(user_id)
  end

  defp profile_form(profile_forms, profile_id), do: Map.fetch!(profile_forms, profile_id)

  defp override_value(nil, _field), do: "inherit"

  defp override_value(preference, field) do
    case Map.get(preference, field) do
      true -> "true"
      false -> "false"
      nil -> "inherit"
    end
  end

  defp effective_summary(effective_preferences, profile_id) do
    preference = Map.fetch!(effective_preferences, profile_id)

    Enum.join(
      [
        String.capitalize(preference.frequency),
        if(preference.include_images, do: "images", else: "no images"),
        if(preference.include_ocr, do: "OCR", else: "no OCR")
      ],
      " · "
    )
  end

  defp normalize_profile_preference_params(params) do
    params
    |> Map.update("include_images", nil, &normalize_override_boolean/1)
    |> Map.update("include_ocr", nil, &normalize_override_boolean/1)
  end

  defp normalize_override_boolean("true"), do: true
  defp normalize_override_boolean("false"), do: false
  defp normalize_override_boolean(_inherit), do: nil

  defp show_daily_options?(form) do
    Form.input_value(form, :frequency) == "daily"
  end

  defp show_weekly_options?(form) do
    Form.input_value(form, :frequency) == "weekly"
  end
end
