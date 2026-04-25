defmodule InstabotWeb.ConnectLive do
  @moduledoc false
  use InstabotWeb, :live_view

  alias Instabot.Scraper.LoginOrchestrator

  @step_order [
    :idle,
    :launching,
    :navigating,
    :logging_in,
    :two_factor,
    :saving,
    :connected,
    :error
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Connect Instagram</h1>
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.link>
        </div>

        <.step_indicator step={@step} />

        <Card.render class="mx-auto w-full sm:w-[480px]">
          <.step_content
            step={@step}
            form={@form}
            two_factor_form={@two_factor_form}
            screenshot={@screenshot}
            error={@error}
          />
        </Card.render>
      </div>
    </Layouts.app>
    """
  end

  defp step_content(%{step: :idle} = assigns) do
    ~H"""
    <h3 class="text-lg font-semibold mb-2">Enter your Instagram credentials</h3>
    <p class="text-sm opacity-70 mb-6">
      Your credentials are encrypted and only used to establish a browser session.
    </p>
    <.form
      for={@form}
      id="credentials-form"
      phx-submit="start_login"
      phx-change="validate_credentials"
      class="flex flex-col gap-y-4"
    >
      <.input field={@form[:username]} type="text" placeholder="Instagram username" required />
      <.input field={@form[:password]} type="password" placeholder="Password" required />
      <.button variant="primary" phx-disable-with="Connecting...">
        Connect Instagram
      </.button>
    </.form>
    """
  end

  defp step_content(%{step: :error} = assigns) do
    ~H"""
    <div class="text-center space-y-4">
      <.icon name="hero-exclamation-triangle" class="size-12 text-error mx-auto" />
      <h3 class="text-lg font-semibold">Login Failed</h3>
      <p class="text-sm opacity-70">{error_message(@error)}</p>
      <.screenshot_preview screenshot={@screenshot} />
      <button phx-click="retry" class="btn btn-primary btn-sm">
        Try Again
      </button>
    </div>
    """
  end

  defp step_content(%{step: :connected} = assigns) do
    ~H"""
    <div class="text-center space-y-4">
      <.icon name="hero-check-circle" class="size-12 text-success mx-auto" />
      <h3 class="text-lg font-semibold">Connected!</h3>
      <p class="text-sm opacity-70">Your Instagram account is now connected.</p>
      <.button navigate={~p"/"} variant="primary">
        Go to Dashboard
      </.button>
    </div>
    """
  end

  defp step_content(%{step: :two_factor} = assigns) do
    ~H"""
    <div class="space-y-4">
      <h3 class="text-lg font-semibold">Two-Factor Authentication</h3>
      <p class="text-sm opacity-70">Enter the security code from your authenticator app or SMS.</p>
      <.screenshot_preview screenshot={@screenshot} />
      <.form
        for={@two_factor_form}
        id="two-factor-form"
        phx-submit="submit_two_factor"
        class="flex flex-col gap-y-4"
      >
        <.input field={@two_factor_form[:code]} type="text" placeholder="6-digit code" required />
        <.button variant="primary" phx-disable-with="Verifying...">
          Verify Code
        </.button>
      </.form>
    </div>
    """
  end

  defp step_content(assigns) do
    ~H"""
    <div class="text-center space-y-4">
      <div class="flex items-center justify-center gap-2">
        <span class="loading loading-spinner loading-md"></span>
        <span class="text-lg font-medium">{step_label(@step)}</span>
      </div>
      <.screenshot_preview screenshot={@screenshot} />
    </div>
    """
  end

  defp step_indicator(assigns) do
    ~H"""
    <div class="flex items-center justify-center gap-2 py-4">
      <.step_dot step={:idle} current={@step} label="Credentials" />
      <.step_connector />
      <.step_dot step={:logging_in} current={@step} label="Login" />
      <.step_connector />
      <.step_dot step={:two_factor} current={@step} label="2FA" />
      <.step_connector />
      <.step_dot step={:connected} current={@step} label="Done" />
    </div>
    """
  end

  attr :step, :atom, required: true
  attr :current, :atom, required: true
  attr :label, :string, required: true

  defp step_dot(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1">
      <div class={["w-3 h-3 rounded-full transition-colors", step_dot_class(@step, @current)]} />
      <span class="text-xs opacity-70">{@label}</span>
    </div>
    """
  end

  defp step_connector(assigns) do
    ~H"""
    <div class="w-8 h-0.5 bg-base-300 mb-4" />
    """
  end

  defp screenshot_preview(assigns) do
    ~H"""
    <div :if={@screenshot} class="rounded-lg overflow-hidden border border-base-300 mx-auto max-w-md">
      <img
        id="login-screenshot"
        src={"data:image/png;base64,#{@screenshot}"}
        alt="Browser screenshot"
        class="w-full"
      />
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Instabot.PubSub, "instagram_login:#{user_id}")
    end

    socket =
      socket
      |> assign(:step, :idle)
      |> assign(:screenshot, nil)
      |> assign(:error, nil)
      |> assign(:task, nil)
      |> assign(:form, to_form(%{"username" => "", "password" => ""}, as: :credentials))
      |> assign(:two_factor_form, to_form(%{"code" => ""}, as: :two_factor))

    {:ok, socket}
  end

  @impl true
  def handle_event("start_login", _params, %{assigns: %{task: task}} = socket) when task != nil do
    {:noreply, socket}
  end

  def handle_event("start_login", %{"credentials" => %{"username" => username, "password" => password}}, socket) do
    user_id = socket.assigns.current_scope.user.id

    task =
      Task.Supervisor.async_nolink(Instabot.TaskSupervisor, fn ->
        LoginOrchestrator.run(user_id, username, password)
      end)

    socket =
      socket
      |> assign(:step, :launching)
      |> assign(:task, task)
      |> assign(:error, nil)
      |> assign(:screenshot, nil)

    {:noreply, socket}
  end

  def handle_event("validate_credentials", %{"credentials" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :credentials))}
  end

  def handle_event("submit_two_factor", %{"two_factor" => %{"code" => code}}, socket) do
    case socket.assigns.task do
      %Task{pid: pid} -> send(pid, {:two_factor_code, code})
      nil -> :ok
    end

    {:noreply, socket}
  end

  def handle_event("retry", _params, socket) do
    socket =
      socket
      |> assign(:step, :idle)
      |> assign(:error, nil)
      |> assign(:screenshot, nil)
      |> assign(:task, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:login_step, step}, socket) do
    {:noreply, assign(socket, :step, step)}
  end

  def handle_info({:login_screenshot, base64}, socket) do
    {:noreply, assign(socket, :screenshot, base64)}
  end

  def handle_info({:login_error, reason}, socket) do
    socket =
      socket
      |> assign(:step, :error)
      |> assign(:error, reason)

    {:noreply, socket}
  end

  def handle_info({ref, _result}, socket) do
    case socket.assigns.task do
      %Task{ref: ^ref} ->
        Process.demonitor(ref, [:flush])
        {:noreply, assign(socket, :task, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{assigns: %{task: %Task{pid: pid}}} = socket)
      when reason != :normal do
    socket =
      socket
      |> assign(:task, nil)
      |> assign(:step, :error)
      |> assign(:error, :task_crashed)

    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{assigns: %{task: %Task{pid: pid}}} = socket) do
    {:noreply, assign(socket, :task, nil)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  defp step_dot_class(dot_step, current_step) do
    dot_index = Enum.find_index(@step_order, &(&1 == dot_step)) || 0
    current_index = Enum.find_index(@step_order, &(&1 == current_step)) || 0

    cond do
      current_step == :error -> "bg-error"
      current_index > dot_index -> "bg-success"
      current_index == dot_index -> "bg-primary"
      true -> "bg-base-300"
    end
  end

  defp step_label(:launching), do: "Starting browser..."
  defp step_label(:navigating), do: "Opening Instagram..."
  defp step_label(:logging_in), do: "Entering credentials..."
  defp step_label(:saving), do: "Saving session..."
  defp step_label(_), do: "Working..."

  defp error_message(:incorrect_password), do: "The password you entered is incorrect."
  defp error_message(:username_not_found), do: "The username was not found."
  defp error_message(:rate_limited), do: "Too many attempts. Please wait a few minutes."

  defp error_message(:suspicious_attempt), do: "Instagram flagged this as suspicious. Try again later."

  defp error_message(:challenge_required), do: "Instagram requires additional verification."
  defp error_message(:two_factor_failed), do: "The 2FA code was incorrect."
  defp error_message(:two_factor_timeout), do: "2FA code entry timed out."
  defp error_message(:task_crashed), do: "An unexpected error occurred."
  defp error_message(:login_failed), do: "Login failed. Please check your credentials."
  defp error_message(_), do: "Something went wrong. Please try again."
end
