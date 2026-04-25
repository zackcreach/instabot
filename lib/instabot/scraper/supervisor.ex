defmodule Instabot.Scraper.Supervisor do
  @moduledoc """
  DynamicSupervisor for managing Browser processes.
  Browser processes are started on demand for scraping jobs and terminated after completion.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Starts a new Browser process under this supervisor."
  @spec start_browser(keyword()) :: DynamicSupervisor.on_start_child()
  def start_browser(opts \\ []) do
    DynamicSupervisor.start_child(__MODULE__, {Instabot.Scraper.Browser, opts})
  end
end
