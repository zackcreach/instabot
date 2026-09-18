defmodule Instabot.Media.StoryVideos do
  @moduledoc "Backfills and verifies locally stored Instagram story videos."

  import Ecto.Query

  alias Instabot.Instagram.Story
  alias Instabot.Media
  alias Instabot.Repo

  @spec backfill() :: {:ok, map()} | {:error, map()}
  def backfill do
    run(&backfill_story/1)
  end

  @spec inventory() :: {:ok, map()} | {:error, map()}
  def inventory do
    run(&inventory_story/1)
  end

  @spec verify() :: {:ok, map()} | {:error, map()}
  def verify do
    run(&verify_story/1)
  end

  defp run(operation) do
    report =
      Story
      |> where([story], story.story_type == "video")
      |> after_legacy_cutoff()
      |> Repo.all()
      |> Enum.reduce(%{records: 0, bytes: 0, migrated: 0, unchanged: 0, failures: []}, fn story, report ->
        update_report(report, story, operation.(story))
      end)

    case report.failures do
      [] -> {:ok, report}
      _failures -> {:error, %{report | failures: Enum.reverse(report.failures)}}
    end
  end

  defp backfill_story(%{media_path: path} = story) when is_binary(path) and path != "" do
    with {:ok, bytes} <- File.read(path),
         :ok <- verify_checksum(bytes, story.media_sha256) do
      {:ok, byte_size(bytes), :unchanged}
    end
  end

  defp backfill_story(story) do
    with true <- present?(story.media_url),
         {:ok, download} <- Media.download(story.media_url),
         {:ok, upload} <- Media.upload_image(download.body, "stories", "#{story.id}.mp4"),
         {:ok, stored_bytes} <- File.read(upload.local_path),
         :ok <- verify_checksum(stored_bytes, upload.checksum),
         {:ok, _story} <-
           story
           |> Ecto.Changeset.change(%{
             media_path: upload.local_path,
             media_content_type: download.content_type,
             media_file_size: upload.file_size,
             media_sha256: upload.checksum
           })
           |> Repo.update() do
      {:ok, byte_size(stored_bytes), :migrated}
    else
      false -> {:error, :source_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp inventory_story(%{media_path: path} = story) when is_binary(path) and path != "" do
    with {:ok, bytes} <- File.read(path),
         :ok <- verify_checksum(bytes, story.media_sha256) do
      {:ok, byte_size(bytes), :unchanged}
    end
  end

  defp inventory_story(story) do
    with true <- present?(story.media_url),
         {:ok, download} <- Media.download(story.media_url) do
      {:ok, byte_size(download.body), :unchanged}
    else
      false -> {:error, :source_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_story(%{media_path: path} = story) when is_binary(path) and path != "" do
    with {:ok, bytes} <- File.read(path),
         :ok <- verify_checksum(bytes, story.media_sha256) do
      {:ok, byte_size(bytes), :unchanged}
    end
  end

  defp verify_story(_story), do: {:error, :media_path_missing}

  defp update_report(report, _story, {:ok, bytes, state}) do
    report
    |> Map.update!(:records, &(&1 + 1))
    |> Map.update!(:bytes, &(&1 + bytes))
    |> Map.update!(state, &(&1 + 1))
  end

  defp update_report(report, story, {:error, reason}) do
    report
    |> Map.update!(:records, &(&1 + 1))
    |> Map.update!(:failures, &[%{id: story.id, reason: inspect(reason)} | &1])
  end

  defp after_legacy_cutoff(query) do
    case Application.get_env(:instabot, :legacy_media_cutoff) do
      %DateTime{} = cutoff -> where(query, [story], story.inserted_at >= ^cutoff)
      nil -> query
    end
  end

  defp verify_checksum(bytes, expected) when is_binary(expected) and expected != "" do
    if checksum(bytes) == expected, do: :ok, else: {:error, :checksum_mismatch}
  end

  defp verify_checksum(_bytes, _expected), do: {:error, :checksum_missing}

  defp checksum(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp present?(value) when is_binary(value), do: value != ""
  defp present?(_value), do: false
end
