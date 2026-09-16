defmodule Instabot.Release do
  @moduledoc """
  Release tasks for production operations without Mix.
  """

  alias Instabot.Media.Migration

  @app :instabot

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def media_inventory do
    run_media_operation(&Migration.inventory/0)
  end

  def backfill_media do
    run_media_operation(&Migration.backfill/0)
  end

  def verify_media do
    run_media_operation(&Migration.verify/0)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    {:ok, _} = Application.ensure_all_started(:ssl)
    Application.load(@app)
  end

  defp run_media_operation(operation) do
    {:ok, _applications} = Application.ensure_all_started(@app)

    case operation.() do
      {:ok, report} ->
        IO.inspect(report, pretty: true, limit: :infinity)
        :ok

      {:error, report} ->
        IO.inspect(report, pretty: true, limit: :infinity)
        raise "media operation failed for #{length(report.failures)} records"
    end
  end
end
