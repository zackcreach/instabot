defmodule Instabot.Media.Url do
  @moduledoc "Builds public original and signed transformation URLs for locally stored media."

  @formats [:jpg, :png, :webp]
  @fits [:fit, :fill, :crop]

  def original_url(storage_key) do
    base_url = Application.fetch_env!(:instabot, :media_base_url)
    encoded_key = encode_storage_key(storage_key)
    "#{base_url}/original/instabot/#{encoded_key}"
  end

  def variant_url(storage_key, options) do
    width = bounded_dimension(Keyword.fetch!(options, :width))
    height = bounded_dimension(Keyword.fetch!(options, :height))
    fit = allowed_value(Keyword.fetch!(options, :fit), @fits)
    quality = bounded_quality(Keyword.fetch!(options, :quality))
    format = allowed_value(Keyword.fetch!(options, :format), @formats)
    version = Keyword.fetch!(options, :version)

    storage_key
    |> local_source_url()
    |> Imgproxy.new()
    |> Imgproxy.resize(width, height, type: Atom.to_string(fit))
    |> Imgproxy.add_option(:quality, [quality])
    |> Imgproxy.add_option(:cachebuster, [version])
    |> Imgproxy.set_extension(Atom.to_string(format))
    |> to_string()
  end

  def feed_thumbnail_url(storage_key, version),
    do: variant_url(storage_key, width: 360, height: 360, fit: :fill, quality: 78, format: :webp, version: version)

  def modal_image_url(storage_key, version),
    do: variant_url(storage_key, width: 1200, height: 1200, fit: :fit, quality: 85, format: :webp, version: version)

  def email_image_url(storage_key, version),
    do: variant_url(storage_key, width: 360, height: 640, fit: :fit, quality: 78, format: :jpg, version: version)

  defp local_source_url(storage_key), do: "local:///instabot/#{encode_storage_key(storage_key)}"

  defp encode_storage_key(storage_key) do
    storage_key
    |> Path.split()
    |> validate_segments()
    |> Enum.map_join("/", &URI.encode(&1, fn character -> URI.char_unreserved?(character) end))
  end

  defp validate_segments([]), do: raise(ArgumentError, "storage key is empty")

  defp validate_segments([segment | _segments]) when segment in [".", "..", "/"],
    do: raise(ArgumentError, "invalid storage key")

  defp validate_segments([segment | segments]), do: [segment | validate_remaining_segments(segments)]

  defp validate_remaining_segments([]), do: []

  defp validate_remaining_segments([segment | _segments]) when segment in [".", "..", "/"],
    do: raise(ArgumentError, "invalid storage key")

  defp validate_remaining_segments([segment | segments]), do: [segment | validate_remaining_segments(segments)]

  defp bounded_dimension(dimension) when is_integer(dimension) and dimension in 1..1600, do: dimension
  defp bounded_dimension(_dimension), do: raise(ArgumentError, "dimension must be between 1 and 1600")

  defp bounded_quality(quality) when is_integer(quality) and quality in 1..100, do: quality
  defp bounded_quality(_quality), do: raise(ArgumentError, "quality must be between 1 and 100")

  defp allowed_value(value, allowed) do
    if Enum.member?(allowed, value) do
      value
    else
      raise ArgumentError, "unsupported media option: #{inspect(value)}"
    end
  end
end
