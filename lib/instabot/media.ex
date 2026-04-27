defmodule Instabot.Media do
  @moduledoc """
  Image download and filesystem management for scraped Instagram media.
  """

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
      Instabot.Media.Cloudinary.download_to_temp(path_or_url, [])
    else
      LocalStorage.download_to_temp(path_or_url, [])
    end
  end

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
