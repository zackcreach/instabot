defmodule InstabotWeb.NotificationSettingsLive do
  @moduledoc false
  use InstabotWeb, :live_view

  alias Instabot.Notifications
  alias Phoenix.HTML.Form

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto w-full sm:w-[500px]">
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
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    preference = Notifications.get_or_create_preference(user.id)
    changeset = Notifications.change_preference(preference)

    socket =
      socket
      |> assign(:preference, preference)
      |> assign(:current_email, user.email)
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

        socket =
          socket
          |> assign(:preference, preference)
          |> assign_form(changeset)
          |> put_flash(:info, "Notification preferences saved.")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp show_daily_options?(form) do
    Form.input_value(form, :frequency) == "daily"
  end

  defp show_weekly_options?(form) do
    Form.input_value(form, :frequency) == "weekly"
  end
end
