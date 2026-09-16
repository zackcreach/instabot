defmodule Instabot.Media.Migration do
  @moduledoc "Inventories, backfills, and verifies local media originals."

  import Ecto.Query

  alias Instabot.Instagram.PostImage
  alias Instabot.Instagram.Story
  alias Instabot.Media
  alias Instabot.Repo
  alias Instabot.Shops.ShopifySnapshot

  @record_types [
    {PostImage, :local_path, [:cloudinary_secure_url, :original_url], :exact_sha256, :file_size},
    {Story, :screenshot_path, [:screenshot_url, :media_url], nil, nil},
    {ShopifySnapshot, :screenshot_path, [:screenshot_url], :screenshot_sha256, nil}
  ]

  @spec inventory() :: {:ok, map()} | {:error, map()}
  def inventory do
    run(:inventory)
  end

  @spec backfill() :: {:ok, map()} | {:error, map()}
  def backfill do
    run(:backfill)
  end

  @spec verify() :: {:ok, map()} | {:error, map()}
  def verify do
    run(:verify)
  end

  defp run(operation) do
    report =
      Enum.reduce(@record_types, initial_report(operation), fn record_type, report ->
        record_type
        |> records()
        |> Enum.reduce(report, &process_record(&1, record_type, operation, &2))
      end)

    case report.failures do
      [] -> {:ok, report}
      _failures -> {:error, %{report | failures: Enum.reverse(report.failures)}}
    end
  end

  defp records({schema, _path_field, _source_fields, _checksum_field, _size_field}), do: Repo.all(from(record in schema))

  defp process_record(record, record_type, operation, report) do
    case process(record, record_type, operation) do
      {:ok, byte_count, state} ->
        report
        |> Map.update!(:records, &(&1 + 1))
        |> Map.update!(:bytes, &(&1 + byte_count))
        |> Map.update!(state, &(&1 + 1))

      {:error, reason} ->
        failure = %{schema: inspect(record.__struct__), id: record.id, reason: inspect(reason)}

        report
        |> Map.update!(:records, &(&1 + 1))
        |> Map.update!(:failures, &[failure | &1])
    end
  end

  defp process(record, record_type, :inventory) do
    with {:ok, bytes, _source} <- verified_bytes(record, record_type) do
      {:ok, byte_size(bytes), :verified}
    end
  end

  defp process(record, record_type, :verify) do
    with {:ok, bytes} <- local_bytes(record, record_type),
         :ok <- verify_local_checksum(bytes, record, record_type) do
      {:ok, byte_size(bytes), :verified}
    end
  end

  defp process(record, record_type, :backfill) do
    case verified_local_bytes(record, record_type) do
      {:ok, bytes} ->
        with :ok <- update_verified_metadata(record, record_type, bytes, path(record, record_type)) do
          {:ok, byte_size(bytes), :unchanged}
        end

      {:error, _local_reason} ->
        backfill_record(record, record_type)
    end
  end

  defp backfill_record(record, record_type) do
    with {:ok, bytes, source} <- remote_bytes(record, record_type),
         :ok <- verify_expected_checksum(bytes, record, record_type),
         {:ok, upload} <- Media.upload_image(bytes, "backfill", source_filename(source, record.id)),
         {:ok, stored_bytes} <- File.read(upload.local_path),
         true <- stored_bytes == bytes,
         :ok <- update_verified_metadata(record, record_type, stored_bytes, upload.local_path) do
      {:ok, byte_size(stored_bytes), :migrated}
    else
      false -> {:error, :reread_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verified_bytes(record, record_type) do
    case verified_local_bytes(record, record_type) do
      {:ok, bytes} ->
        {:ok, bytes, path(record, record_type)}

      {:error, _local_reason} ->
        remote_bytes(record, record_type)
    end
  end

  defp verified_local_bytes(record, record_type) do
    with {:ok, bytes} <- local_bytes(record, record_type),
         :ok <- verify_local_checksum(bytes, record, record_type) do
      {:ok, bytes}
    end
  end

  defp local_bytes(record, {_schema, path_field, _source_fields, _checksum_field, _size_field}) do
    case Map.get(record, path_field) do
      local_path when is_binary(local_path) and local_path != "" -> File.read(local_path)
      _missing -> {:error, :local_path_missing}
    end
  end

  defp remote_bytes(record, {_schema, _path_field, source_fields, _checksum_field, _size_field}) do
    sources =
      source_fields
      |> Enum.map(&Map.get(record, &1))
      |> Enum.filter(&present?/1)

    case sources do
      [] -> {:error, :source_missing}
      available_sources -> try_remote_sources(available_sources, [])
    end
  end

  defp read_remote_source(source) do
    case Media.download(source) do
      {:ok, %{body: bytes}} -> {:ok, bytes, source}
      {:error, reason} -> {:error, {:download_failed, reason}}
    end
  end

  defp try_remote_sources([], failures), do: {:error, {:sources_failed, Enum.reverse(failures)}}

  defp try_remote_sources([source | sources], failures) do
    case read_remote_source(source) do
      {:ok, bytes, verified_source} -> {:ok, bytes, verified_source}
      {:error, reason} -> try_remote_sources(sources, [{source, reason} | failures])
    end
  end

  defp verify_expected_checksum(bytes, record, {_schema, _path_field, _source_fields, checksum_field, _size_field}) do
    expected_checksum = checksum_field && Map.get(record, checksum_field)
    actual_checksum = checksum(bytes)

    case expected_checksum do
      value when is_binary(value) and value != "" and value != actual_checksum -> {:error, :checksum_mismatch}
      _matches_or_unknown -> :ok
    end
  end

  defp verify_local_checksum(bytes, record, record_type) do
    with :ok <- verify_expected_checksum(bytes, record, record_type) do
      verify_content_address(bytes, path(record, record_type))
    end
  end

  defp verify_content_address(bytes, local_path) do
    local_path
    |> Path.basename()
    |> Path.rootname()
    |> case do
      <<expected_checksum::binary-size(64)>> ->
        if String.match?(expected_checksum, ~r/^[0-9a-f]{64}$/) and checksum(bytes) != expected_checksum do
          {:error, :content_address_mismatch}
        else
          :ok
        end

      _legacy_name ->
        :ok
    end
  end

  defp update_verified_metadata(
         record,
         {_schema, path_field, _source_fields, checksum_field, size_field},
         bytes,
         local_path
       ) do
    attrs =
      %{path_field => local_path}
      |> maybe_put(checksum_field, checksum(bytes))
      |> maybe_put(size_field, byte_size(bytes))

    record
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
    |> case do
      {:ok, _record} -> :ok
      {:error, changeset} -> {:error, {:update_failed, changeset.errors}}
    end
  end

  defp path(record, {_schema, path_field, _source_fields, _checksum_field, _size_field}), do: Map.get(record, path_field)

  defp source_filename(source, record_id) do
    extension = source |> URI.parse() |> Map.get(:path, "") |> Path.extname()
    "#{record_id}#{extension}"
  end

  defp initial_report(operation) do
    %{operation: operation, records: 0, bytes: 0, verified: 0, migrated: 0, unchanged: 0, failures: []}
  end

  defp checksum(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp maybe_put(attrs, nil, _value), do: attrs
  defp maybe_put(attrs, field, value), do: Map.put(attrs, field, value)

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(_value), do: false
end
