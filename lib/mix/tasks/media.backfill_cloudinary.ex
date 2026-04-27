defmodule Mix.Tasks.Media.BackfillCloudinary do
  @shortdoc "Backfills Cloudinary URLs for legacy local media"

  @moduledoc """
  Uploads legacy local media files to the configured media storage adapter.
  """

  use Mix.Task

  import Ecto.Query

  alias Instabot.Instagram.PostImage
  alias Instabot.Instagram.Story
  alias Instabot.Media
  alias Instabot.Repo

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    post_results = backfill_post_images()
    story_results = backfill_stories()

    IO.puts("Post images: #{format_counts(post_results)}")
    IO.puts("Stories: #{format_counts(story_results)}")
  end

  defp backfill_post_images do
    PostImage
    |> where([image], is_nil(image.cloudinary_secure_url) and not is_nil(image.local_path))
    |> Repo.all()
    |> Enum.map(&backfill_post_image/1)
    |> Enum.frequencies()
  end

  defp backfill_post_image(%PostImage{} = post_image) do
    with {:ok, bytes} <- read_legacy_file(post_image.local_path),
         {:ok, upload} <-
           Media.upload_image(bytes, post_image.post_id, Path.basename(post_image.local_path),
             content_type: post_image.content_type,
             public_id: Path.join(post_image.post_id, Path.rootname(Path.basename(post_image.local_path)))
           ),
         {:ok, _post_image} <-
           post_image
           |> Ecto.Changeset.change(%{
             cloudinary_public_id: upload[:cloudinary_public_id],
             cloudinary_secure_url: upload[:cloudinary_secure_url],
             cloudinary_version: upload[:cloudinary_version],
             cloudinary_format: upload[:cloudinary_format],
             cloudinary_resource_type: upload[:cloudinary_resource_type],
             width: upload[:width],
             height: upload[:height]
           })
           |> Repo.update() do
      :uploaded
    else
      {:error, :enoent} -> :missing
      {:error, _reason} -> :failed
    end
  end

  defp backfill_stories do
    Story
    |> where([story], is_nil(story.screenshot_url) and not is_nil(story.screenshot_path))
    |> Repo.all()
    |> Enum.map(&backfill_story/1)
    |> Enum.frequencies()
  end

  defp backfill_story(%Story{} = story) do
    with {:ok, bytes} <- read_legacy_file(story.screenshot_path),
         {:ok, upload} <-
           Media.upload_image(bytes, Path.join("stories", story.tracked_profile_id), Path.basename(story.screenshot_path),
             content_type: "image/png",
             public_id:
               Path.join(["stories", story.tracked_profile_id, Path.rootname(Path.basename(story.screenshot_path))])
           ),
         {:ok, _story} <-
           story
           |> Ecto.Changeset.change(%{
             screenshot_url: upload[:cloudinary_secure_url],
             screenshot_cloudinary_public_id: upload[:cloudinary_public_id],
             screenshot_cloudinary_version: upload[:cloudinary_version],
             screenshot_cloudinary_format: upload[:cloudinary_format],
             screenshot_width: upload[:width],
             screenshot_height: upload[:height]
           })
           |> Repo.update() do
      :uploaded
    else
      {:error, :enoent} -> :missing
      {:error, _reason} -> :failed
    end
  end

  defp read_legacy_file(path) do
    path
    |> Media.to_url()
    |> local_path_candidates(path)
    |> Enum.find_value(fn candidate ->
      case File.read(candidate) do
        {:ok, bytes} -> {:ok, bytes}
        {:error, _reason} -> nil
      end
    end)
    |> case do
      {:ok, bytes} -> {:ok, bytes}
      nil -> {:error, :enoent}
    end
  end

  defp local_path_candidates("/" <> relative_path, original_path),
    do: [original_path, Path.join("priv/static", relative_path)]

  defp local_path_candidates(_url, original_path), do: [original_path]

  defp format_counts(counts) do
    Enum.map_join([:uploaded, :missing, :failed], ", ", fn status -> "#{status}=#{Map.get(counts, status, 0)}" end)
  end
end
