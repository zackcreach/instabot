defmodule Instabot.Scraper.Browser do
  @moduledoc """
  GenServer wrapping a Port to the Playwright Node.js bridge.
  Provides synchronous command execution with request/response correlation.
  """

  use GenServer

  require Logger

  defstruct [:port, :pending, :next_id, :buffer, :config]

  @type state :: %__MODULE__{
          port: port() | nil,
          pending: %{String.t() => {GenServer.from(), reference()}},
          next_id: pos_integer(),
          buffer: String.t(),
          config: map()
        }

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Launches the Chromium browser with the given options."
  @spec launch(pid(), keyword()) :: {:ok, map()} | {:error, term()}
  def launch(pid, opts \\ []) do
    call(pid, :launch, Map.new(opts))
  end

  @doc "Creates a new browser page with optional user agent and viewport."
  @spec new_page(pid(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def new_page(pid, opts \\ []) do
    with {:ok, data} <- call(pid, :new_page, Map.new(opts)) do
      {:ok, data["page_id"]}
    end
  end

  @doc "Navigates a page to the given URL."
  @spec navigate(pid(), String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def navigate(pid, page_id, url, opts \\ []) do
    params =
      opts
      |> Map.new()
      |> Map.merge(%{page_id: page_id, url: url})

    call(pid, :navigate, params)
  end

  @doc "Takes a screenshot of the page. Returns base64-encoded image data."
  @spec screenshot(pid(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def screenshot(pid, page_id, opts \\ []) do
    params =
      opts
      |> Map.new()
      |> Map.put(:page_id, page_id)

    call(pid, :screenshot, params)
  end

  @doc "Sets cookies on the page's browser context."
  @spec set_cookies(pid(), String.t(), [map()]) :: {:ok, map()} | {:error, term()}
  def set_cookies(pid, page_id, cookies) do
    call(pid, :set_cookies, %{page_id: page_id, cookies: cookies})
  end

  @doc "Gets all cookies from the page's browser context."
  @spec get_cookies(pid(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def get_cookies(pid, page_id) do
    with {:ok, data} <- call(pid, :get_cookies, %{page_id: page_id}) do
      {:ok, data["cookies"]}
    end
  end

  @doc "Gets the full storage state (cookies + localStorage) from the page's browser context."
  @spec get_storage_state(pid(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_storage_state(pid, page_id) do
    with {:ok, data} <- call(pid, :get_storage_state, %{page_id: page_id}) do
      {:ok, data["storage_state"]}
    end
  end

  @doc "Restores full storage state (cookies + localStorage) into the page's browser context."
  @spec restore_storage_state(pid(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def restore_storage_state(pid, page_id, storage_state) do
    call(pid, :restore_storage_state, %{page_id: page_id, storage_state: storage_state})
  end

  @doc "Evaluates a JavaScript expression in the page context."
  @spec evaluate(pid(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def evaluate(pid, page_id, expression) do
    with {:ok, data} <- call(pid, :evaluate, %{page_id: page_id, expression: expression}) do
      {:ok, data["result"]}
    end
  end

  @doc "Gets the full HTML content of the page."
  @spec get_page_content(pid(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_page_content(pid, page_id) do
    with {:ok, data} <- call(pid, :get_page_content, %{page_id: page_id}) do
      {:ok, data["content"]}
    end
  end

  @doc "Gets captured JSON network responses for a page."
  @spec get_json_responses(pid(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def get_json_responses(pid, page_id, opts \\ []) do
    params =
      opts
      |> Map.new()
      |> Map.put(:page_id, page_id)

    with {:ok, data} <- call(pid, :get_json_responses, params) do
      {:ok, data["responses"] || []}
    end
  end

  @doc "Clicks an element matching the selector."
  @spec click(pid(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def click(pid, page_id, selector) do
    call(pid, :click, %{page_id: page_id, selector: selector})
  end

  @doc "Types text into an element matching the selector."
  @spec type_text(pid(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def type_text(pid, page_id, selector, text, opts \\ []) do
    params =
      opts
      |> Map.new()
      |> Map.merge(%{page_id: page_id, selector: selector, text: text})

    call(pid, :type, params)
  end

  @doc "Presses a keyboard key on the page."
  @spec keyboard_press(pid(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def keyboard_press(pid, page_id, key) do
    call(pid, :keyboard_press, %{page_id: page_id, key: key})
  end

  @doc "Waits for an element matching the selector to appear."
  @spec wait_for_selector(pid(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def wait_for_selector(pid, page_id, selector, opts \\ []) do
    params =
      opts
      |> Map.new()
      |> Map.merge(%{page_id: page_id, selector: selector})

    call(pid, :wait_for_selector, params)
  end

  @doc "Closes a specific page or the entire browser if no page_id is given."
  @spec close(pid(), keyword()) :: {:ok, map()} | {:error, term()}
  def close(pid, opts \\ []) do
    call(pid, :close, Map.new(opts))
  end

  @doc "Stops the Browser GenServer."
  @spec stop(pid()) :: :ok
  def stop(pid) do
    GenServer.stop(pid, :normal)
  catch
    :exit, _reason -> :ok
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    config = scraper_config()
    playwright_path = config[:playwright_path]
    node_path = System.find_executable(config[:node_path]) || config[:node_path]
    bridge_script = config[:bridge_script] || Path.join(playwright_path, "playwright_bridge.js")

    port =
      Port.open(
        {:spawn_executable, node_path},
        [
          :binary,
          :exit_status,
          :use_stdio,
          {:args, [bridge_script]},
          {:cd, playwright_path}
        ]
      )

    state = %__MODULE__{
      port: port,
      pending: %{},
      next_id: 1,
      buffer: "",
      config: Map.new(config)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:command, command, params}, from, state) do
    command_id = Integer.to_string(state.next_id)
    timeout = state.config[:command_timeout] || 15_000

    request = Jason.encode!(%{id: command_id, command: command, params: params})

    Port.command(state.port, request <> "\n")

    timer_ref = Process.send_after(self(), {:command_timeout, command_id}, timeout)

    updated_pending = Map.put(state.pending, command_id, {from, timer_ref})

    {:noreply, %{state | pending: updated_pending, next_id: state.next_id + 1}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    buffer = state.buffer <> data
    {complete_lines, remaining} = split_buffer(buffer)

    updated_state =
      Enum.reduce(complete_lines, %{state | buffer: remaining}, fn line, acc ->
        handle_response_line(line, acc)
      end)

    {:noreply, updated_state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("Playwright bridge exited with status #{status}")

    Enum.each(state.pending, fn {_id, {from, timer_ref}} ->
      Process.cancel_timer(timer_ref)
      GenServer.reply(from, {:error, :port_crashed})
    end)

    {:stop, {:port_crashed, status}, %{state | pending: %{}, port: nil}}
  end

  def handle_info({:command_timeout, command_id}, state) do
    case Map.pop(state.pending, command_id) do
      {{from, _timer_ref}, updated_pending} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending: updated_pending}}

      {nil, _pending} ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, %{port: port} = _state) when is_port(port) do
    close_command = Jason.encode!(%{id: "shutdown", command: "close", params: %{}})

    Port.command(port, close_command <> "\n")

    try do
      Port.close(port)
    rescue
      ArgumentError -> :ok
    end
  end

  def terminate(_reason, _state), do: :ok

  # --- Private ---

  defp call(pid, command, params) do
    GenServer.call(pid, {:command, command, params}, :infinity)
  end

  defp split_buffer(buffer) do
    case String.split(buffer, "\n") do
      [single] ->
        {[], single}

      parts ->
        {complete, [remaining]} = Enum.split(parts, -1)
        {Enum.reject(complete, &(&1 == "")), remaining}
    end
  end

  defp handle_response_line(line, state) do
    case Jason.decode(line) do
      {:ok, %{"id" => id, "status" => "ok", "data" => data}} ->
        reply_to_pending(state, id, {:ok, data})

      {:ok, %{"id" => id, "status" => "error", "error" => error}} ->
        reply_to_pending(state, id, {:error, error})

      {:error, _decode_error} ->
        Logger.warning("Failed to decode bridge response: #{inspect(line)}")
        state
    end
  end

  defp reply_to_pending(state, command_id, reply) do
    case Map.pop(state.pending, command_id) do
      {{from, timer_ref}, updated_pending} ->
        Process.cancel_timer(timer_ref)
        GenServer.reply(from, reply)
        %{state | pending: updated_pending}

      {nil, _pending} ->
        Logger.warning("Received response for unknown command ID: #{command_id}")
        state
    end
  end

  defp scraper_config do
    Application.get_env(:instabot, Instabot.Scraper, [])
  end
end
