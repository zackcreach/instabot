defmodule Instabot.Media do
  @moduledoc """
  Image download and filesystem management for scraped Instagram media.
  """

  @default_uploads_dir "priv/static/uploads"

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
