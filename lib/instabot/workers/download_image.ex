defmodule Instabot.Workers.DownloadImage do
  @moduledoc """
  Downloads a single image from a URL and saves it locally as a PostImage record.
  """

  use Oban.Worker, queue: :media, max_attempts: 3

  alias Instabot.Instagram
  alias Instabot.Media

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"post_id" => post_id, "url" => url, "position" => position}}) do
    extension = url_extension(url)
    filename = "image_#{position}#{extension}"

    with {:ok, result} <- Media.download_and_upload(url, post_id, filename),
         {:ok, _post_image} <-
           Instagram.create_post_image(post_id, %{
             original_url: url,
             local_path: result[:local_path],
             position: position,
             content_type: result.content_type,
             file_size: result.file_size,
             cloudinary_public_id: result[:cloudinary_public_id],
             cloudinary_secure_url: result[:cloudinary_secure_url],
             cloudinary_version: result[:cloudinary_version],
             cloudinary_format: result[:cloudinary_format],
             cloudinary_resource_type: result[:cloudinary_resource_type],
             width: result[:width],
             height: result[:height]
           }) do
      :ok
    end
  end

  defp url_extension(url) do
    extension =
      url
      |> URI.parse()
      |> Map.get(:path, "")
      |> Path.extname()
      |> String.downcase()

    case extension do
      "" -> ".jpg"
      ext -> ext
    end
  end
end
