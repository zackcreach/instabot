defmodule Instabot.Media do
  @moduledoc """
  Image download and filesystem management for scraped Instagram media.
  """

  alias Instabot.Media.Cloudinary
  alias Instabot.Media.LocalStorage

  @default_uploads_dir "priv/static/uploads"
  @default_storage_adapter LocalStorage

  @spec uploads_dir() :: String.t()
  def uploads_dir do
    Application.get_env(:instabot, :uploads_dir, @default_uploads_dir)
  end

  @spec download_and_save(String.t(), String.t(), String.t()) ::
          {:ok, %{local_path: String.t(), content_type: String.t(), file_size: integer()}}
          | {:error, term()}
  def download_and_save(url, subdirectory, filename) do
    target_dir = Path.join(uploads_dir(), subdirectory)

    with :ok <- ensure_directory(target_dir),
         {:ok, response} <- fetch(url) do
      local_path = Path.join(target_dir, filename)
      content_type = extract_content_type(response.headers, url)
      file_size = byte_size(response.body)

      case File.write(local_path, response.body) do
        :ok ->
          {:ok, %{local_path: local_path, content_type: content_type, file_size: file_size}}

        {:error, reason} ->
          {:error, {:write_failed, reason}}
      end
    end
  end

  @spec download_and_upload(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def download_and_upload(url, subdirectory, filename) do
    with {:ok, response} <- fetch(url) do
      content_type = extract_content_type(response.headers, url)

      response.body
      |> upload_image(subdirectory, filename,
        content_type: content_type,
        public_id: Path.join(subdirectory, Path.rootname(filename))
      )
      |> merge_upload_metadata(%{
        original_url: url,
        content_type: content_type,
        file_size: byte_size(response.body)
      })
    end
  end

  @spec upload_image(binary(), String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def upload_image(bytes, subdirectory, filename, opts \\ []) when is_binary(bytes) do
    opts =
      opts
      |> Keyword.put(:subdirectory, subdirectory)
      |> Keyword.put(:filename, filename)
      |> Keyword.put_new(:public_id, Path.join(subdirectory, Path.rootname(filename)))

    storage_adapter().upload_image(bytes, opts)
  end

  @spec download_to_temp(String.t()) :: {:ok, String.t()} | {:error, term()}
  def download_to_temp(path_or_url) when is_binary(path_or_url) do
    if String.starts_with?(path_or_url, "http://") or String.starts_with?(path_or_url, "https://") do
      Cloudinary.download_to_temp(path_or_url, [])
    else
      LocalStorage.download_to_temp(path_or_url, [])
    end
  end

  @spec cloudinary_storage?() :: boolean()
  def cloudinary_storage?, do: storage_adapter() == Cloudinary

  @spec post_image_urls(map()) :: [String.t()]
  def post_image_urls(%{post_images: post_images} = post) when is_list(post_images) and post_images != [] do
    post_images
    |> Enum.sort_by(& &1.position)
    |> Enum.map(&post_image_url/1)
    |> Enum.reject(&is_nil/1)
    |> fallback_post_media_urls(post)
  end

  def post_image_urls(%{media_urls: media_urls}) when is_list(media_urls) do
    Enum.reject(media_urls, &blank?/1)
  end

  def post_image_urls(_post), do: []

  @spec post_thumbnail_url(map()) :: String.t() | nil
  def post_thumbnail_url(post) do
    post
    |> post_image_urls()
    |> List.first()
  end

  @spec post_image_count(map()) :: non_neg_integer()
  def post_image_count(post), do: post |> post_image_urls() |> length()

  @spec post_image_url_at(map(), non_neg_integer()) :: String.t() | nil
  def post_image_url_at(post, index) do
    post
    |> post_image_urls()
    |> Enum.at(index)
  end

  @spec story_preview_url(map(), keyword()) :: String.t() | nil
  def story_preview_url(story, opts \\ []) do
    local_path = local_story_path(story, opts)
    media_url = loadable_story_media_url(story, opts)

    Enum.find_value([Map.get(story, :screenshot_url), local_path, media_url], &present_media_url/1)
  end

  @spec story_has_screenshot?(map()) :: boolean()
  def story_has_screenshot?(%{screenshot_url: screenshot_url}) when is_binary(screenshot_url) and screenshot_url != "",
    do: true

  def story_has_screenshot?(%{screenshot_path: screenshot_path})
      when is_binary(screenshot_path) and screenshot_path != "", do: true

  def story_has_screenshot?(_story), do: false

  @spec ensure_directory(String.t()) :: :ok | {:error, term()}
  def ensure_directory(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  @spec to_url(String.t() | nil) :: String.t() | nil
  def to_url(nil), do: nil

  def to_url(path) do
    case String.split(path, "priv/static/", parts: 2) do
      [_, relative] -> "/" <> relative
      _ -> path
    end
  end

  @spec local_static_path_exists?(String.t()) :: boolean()
  def local_static_path_exists?(path) do
    cond do
      String.contains?(path, "priv/static/") ->
        [_, relative_path] = String.split(path, "priv/static/", parts: 2)
        File.exists?(path) or File.exists?(Path.join("priv/static", relative_path))

      String.starts_with?(path, "http") ->
        false

      String.starts_with?(path, "/") ->
        path
        |> String.trim_leading("/")
        |> then(&Path.join("priv/static", &1))
        |> File.exists?()

      true ->
        File.exists?(path) or File.exists?(Path.join("priv/static", path))
    end
  end

  @spec delete_file(String.t()) :: :ok | {:error, term()}
  def delete_file(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp storage_adapter do
    :instabot
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:storage_adapter, @default_storage_adapter)
  end

  defp post_image_url(%{cloudinary_secure_url: url}) when is_binary(url) and url != "", do: to_url(url)
  defp post_image_url(%{local_path: path}) when is_binary(path) and path != "", do: to_url(path)
  defp post_image_url(_post_image), do: nil

  defp fallback_post_media_urls([], post), do: post_image_urls(Map.take(post, [:media_urls]))
  defp fallback_post_media_urls(urls, _post), do: urls

  defp local_story_path(%{screenshot_path: screenshot_path}, opts)
       when is_binary(screenshot_path) and screenshot_path != "" do
    if Keyword.get(opts, :require_local_exists, false) do
      if local_static_path_exists?(screenshot_path), do: screenshot_path
    else
      screenshot_path
    end
  end

  defp local_story_path(_story, _opts), do: nil

  defp loadable_story_media_url(%{media_url: media_url}, opts) when is_binary(media_url) and media_url != "" do
    blocked_hosts = Keyword.get(opts, :blocked_hosts, [])

    if loadable_media_url?(media_url, blocked_hosts), do: media_url
  end

  defp loadable_story_media_url(_story, _opts), do: nil

  defp loadable_media_url?(url, []), do: present?(url)

  defp loadable_media_url?(url, blocked_hosts) do
    case URI.parse(url) do
      %{host: host} when is_binary(host) ->
        Enum.all?(blocked_hosts, fn blocked_host -> not String.ends_with?(host, blocked_host) end)

      _ ->
        true
    end
  end

  defp present_media_url(value) when is_binary(value) and value != "", do: to_url(value)
  defp present_media_url(_value), do: nil

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(_value), do: false

  defp blank?(value) when is_binary(value), do: value == ""
  defp blank?(_value), do: true

  defp merge_upload_metadata({:ok, upload}, metadata), do: {:ok, Map.merge(metadata, upload)}
  defp merge_upload_metadata({:error, reason}, _metadata), do: {:error, reason}

  defp fetch(url) do
    case Req.get(url, decode_body: false, max_retries: 2) do
      {:ok, %Req.Response{status: 200} = response} ->
        {:ok, response}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_content_type(headers, url) do
    case Map.get(headers, "content-type") do
      [value | _] -> value |> String.split(";") |> List.first() |> String.trim()
      _ -> content_type_from_extension(url)
    end
  end

  defp content_type_from_extension(url) do
    url
    |> URI.parse()
    |> Map.get(:path, "")
    |> Path.extname()
    |> String.downcase()
    |> case do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".mp4" -> "video/mp4"
      _ -> "application/octet-stream"
    end
  end
end
