defmodule Instabot.Media.LocalStorage do
  @moduledoc """
  Local filesystem storage adapter for development, tests, and legacy fallback.
  """

  @behaviour Instabot.Media.Storage

  @impl true
  def upload_image(bytes, opts) when is_binary(bytes) do
    filename = Keyword.fetch!(opts, :filename)
    checksum = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
    storage_key = Path.join([String.slice(checksum, 0, 2), checksum <> normalized_extension(filename)])
    local_path = Path.join(Instabot.Media.uploads_dir(), storage_key)
    target_dir = Path.dirname(local_path)

    with :ok <- Instabot.Media.ensure_directory(target_dir),
         :ok <- write_file(local_path, bytes, checksum),
         :ok <- verify_file(local_path, checksum) do
      {:ok,
       %{
         local_path: local_path,
         storage_key: storage_key,
         checksum: checksum,
         version: checksum,
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

  defp write_file(path, bytes, checksum) do
    case verify_existing_file(path, checksum) do
      :missing -> write_new_file(path, bytes, checksum)
      result -> result
    end
  end

  defp write_new_file(path, bytes, checksum) do
    temporary_path = "#{path}.#{System.unique_integer([:positive])}.tmp"

    with :ok <- File.write(temporary_path, bytes, [:binary, :exclusive]),
         :ok <- verify_file(temporary_path, checksum),
         :ok <- link_or_verify(temporary_path, path, checksum),
         :ok <- File.rm(temporary_path) do
      :ok
    else
      {:error, reason} ->
        File.rm(temporary_path)
        {:error, {:write_failed, reason}}
    end
  end

  defp link_or_verify(temporary_path, path, checksum) do
    case File.ln(temporary_path, path) do
      :ok -> :ok
      {:error, :eexist} -> verify_existing_file(path, checksum)
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_existing_file(path, checksum) do
    case File.read(path) do
      {:ok, bytes} -> verify_checksum(bytes, checksum)
      {:error, :enoent} -> :missing
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_file(path, checksum) do
    case File.read(path) do
      {:ok, bytes} -> verify_checksum(bytes, checksum)
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_checksum(bytes, checksum) do
    if Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == checksum do
      :ok
    else
      {:error, :checksum_collision}
    end
  end

  defp normalized_extension(filename) do
    filename
    |> Path.extname()
    |> String.downcase()
  end
end
