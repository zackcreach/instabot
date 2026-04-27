defmodule Instabot.Media.LocalStorage do
  @moduledoc """
  Local filesystem storage adapter for development, tests, and legacy fallback.
  """

  @behaviour Instabot.Media.Storage

  @impl true
  def upload_image(bytes, opts) when is_binary(bytes) do
    subdirectory = Keyword.fetch!(opts, :subdirectory)
    filename = Keyword.fetch!(opts, :filename)
    target_dir = Path.join(Instabot.Media.uploads_dir(), subdirectory)
    local_path = Path.join(target_dir, filename)

    with :ok <- Instabot.Media.ensure_directory(target_dir),
         :ok <- write_file(local_path, bytes) do
      {:ok,
       %{
         local_path: local_path,
         file_size: byte_size(bytes),
         width: nil,
         height: nil
       }}
    end
  end

  @impl true
  def download_to_temp(path, _opts) when is_binary(path) do
    if File.exists?(path) do
      {:ok, path}
    else
      {:error, :file_not_found}
    end
  end

  defp write_file(path, bytes) do
    case File.write(path, bytes) do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_failed, reason}}
    end
  end
end
