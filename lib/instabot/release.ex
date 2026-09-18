defmodule Instabot.Release do
  @moduledoc """
  Release tasks for production operations without Mix.
  """

  alias Instabot.Media.Migration
  alias Instabot.Media.StoryVideos

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
    run_media_operations([&Migration.inventory/0, &StoryVideos.inventory/0])
  end

  def backfill_media do
    run_media_operations([&Migration.backfill/0, &StoryVideos.backfill/0])
  end

  def verify_media do
    run_media_operations([&Migration.verify/0, &StoryVideos.verify/0])
  end

  def backfill_story_videos do
    run_media_operation(&StoryVideos.backfill/0)
  end

  def verify_story_videos do
    run_media_operation(&StoryVideos.verify/0)
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
        print_media_report(report)
        :ok

      {:error, report} ->
        print_media_report(report)
        raise "media operation failed for #{length(report.failures)} records"
    end
  end

  defp run_media_operations(operations) do
    Enum.each(operations, &run_media_operation/1)
  end

  defp print_media_report(report) do
    Enum.each(report.failures, &IO.inspect(&1, label: "media failure"))

    report
    |> Map.put(:failures, length(report.failures))
    |> IO.inspect(label: "media summary")
  end
end
