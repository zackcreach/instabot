defmodule Instabot.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      InstabotWeb.Telemetry,
      Instabot.Repo,
      {Oban, Application.fetch_env!(:instabot, Oban)},
      {DNSCluster, query: Application.get_env(:instabot, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Instabot.PubSub},
      Instabot.Scraper.Supervisor,
      {Task.Supervisor, name: Instabot.TaskSupervisor},
      InstabotWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Instabot.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    InstabotWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
