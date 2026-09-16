defmodule Mix.Tasks.Media.Backfill do
  @shortdoc "Backfills Cloudinary and legacy media into local content-addressed storage"

  @moduledoc false
  use Mix.Task

  @impl Mix.Task
  def run(_arguments) do
    Mix.Task.run("app.start")

    case Instabot.Media.Migration.backfill() do
      {:ok, report} -> Mix.shell().info(inspect(report, pretty: true, limit: :infinity))
      {:error, report} -> Mix.raise(inspect(report, pretty: true, limit: :infinity))
    end
  end
end
