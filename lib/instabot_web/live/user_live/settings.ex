defmodule InstabotWeb.UserLive.Settings do
  @moduledoc false
  use InstabotWeb, :live_view

  alias Instabot.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto w-full sm:w-[400px]">
        <Card.render>
          <h3 class="text-lg font-semibold">Account Settings</h3>
          <p class="text-sm mt-2 mb-4">Manage your account email address and password settings.</p>

          <div class="flex flex-col gap-y-12">
            <div>
              <h4 class="font-semibold mb-2">Account</h4>
              <div class="flex items-center justify-between gap-4 rounded-lg bg-base-200 px-4 py-3">
                <span class="min-w-0 truncate text-sm opacity-80">{@current_email}</span>
                <.link href={~p"/users/log-out"} method="delete" class="btn btn-ghost btn-sm shrink-0">
                  Log out
                </.link>
              </div>
            </div>

            <div>
              <h4 class="font-semibold mb-2">Appearance</h4>
              <p class="text-sm opacity-70 mb-3">Choose the color theme for this browser.</p>
              <div id="theme-settings" class="w-36">
                <Layouts.theme_toggle />
              </div>
            </div>

            <div>
              <.form
                for={@email_form}
                id="email_form"
                phx-submit="update_email"
                phx-change="validate_email"
                class="flex flex-col gap-y-4"
              >
                <.input
                  field={@email_form[:email]}
                  type="email"
                  placeholder="Email"
                  autocomplete="username"
                  spellcheck="false"
                  required
                />
                <.button phx-disable-with="Changing..." class="btn btn-primary w-full">
                  Change email
                </.button>
              </.form>
            </div>
            <div>
              <.form
                for={@password_form}
                id="password_form"
                action={~p"/users/update-password"}
                method="post"
                phx-change="validate_password"
                phx-submit="update_password"
                phx-trigger-action={@trigger_submit}
                class="flex flex-col gap-y-4"
              >
                <input
                  name={@password_form[:email].name}
                  type="hidden"
                  id="hidden_user_email"
                  spellcheck="false"
                  value={@current_email}
                />
                <.input
                  field={@password_form[:password]}
                  type="password"
                  placeholder="New password"
                  autocomplete="new-password"
                  spellcheck="false"
                  required
                />
                <.input
                  field={@password_form[:password_confirmation]}
                  type="password"
                  placeholder="Confirm new password"
                  autocomplete="new-password"
                  spellcheck="false"
                />
                <.button phx-disable-with="Saving..." class="btn btn-primary w-full">
                  Change password
                </.button>
              </.form>
            </div>
          </div>
        </Card.render>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      case Accounts.change_user_email(user, user_params) do
        %{valid?: true} = changeset ->
          Accounts.deliver_user_update_email_instructions(
            Ecto.Changeset.apply_action!(changeset, :insert),
            user.email,
            &url(~p"/users/settings/confirm-email/#{&1}")
          )

          info = "A link to confirm your email change has been sent to the new address."
          {:noreply, put_flash(socket, :info, info)}

        changeset ->
          {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
      end
    else
      {:noreply, require_reauthentication(socket)}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      case Accounts.change_user_password(user, user_params) do
        %{valid?: true} = changeset ->
          {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

        changeset ->
          {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
      end
    else
      {:noreply, require_reauthentication(socket)}
    end
  end

  defp require_reauthentication(socket) do
    socket
    |> put_flash(:error, "You must re-authenticate before changing account settings.")
    |> redirect(to: ~p"/users/log-in")
  end
end
