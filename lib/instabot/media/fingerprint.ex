defmodule Instabot.Media.Fingerprint do
  @moduledoc """
  Computes exact and perceptual fingerprints for image bytes.
  """

  @default_hamming_threshold 12

  @type t :: %{
          exact_sha256: String.t(),
          dhash: String.t(),
          width: pos_integer() | nil,
          height: pos_integer() | nil
        }

  @spec default_hamming_threshold() :: non_neg_integer()
  def default_hamming_threshold, do: @default_hamming_threshold

  @spec from_bytes(binary()) :: {:ok, t()} | {:error, term()}
  def from_bytes(bytes) when is_binary(bytes) do
    with magick when is_binary(magick) <- System.find_executable("magick"),
         {:ok, path} <- write_temp_image(bytes) do
      try do
        with {:ok, dimensions} <- image_dimensions(magick, path),
             {:ok, dhash} <- image_dhash(magick, path) do
          {:ok,
           %{
             exact_sha256: sha256(bytes),
             dhash: dhash,
             width: dimensions.width,
             height: dimensions.height
           }}
        end
      after
        File.rm(path)
      end
    else
      nil -> {:error, :magick_not_installed}
      {:error, _reason} = error -> error
    end
  end

  @spec duplicate?(t() | map(), t() | map(), keyword()) :: boolean()
  def duplicate?(left, right, opts \\ []) do
    threshold = Keyword.get(opts, :hamming_threshold, @default_hamming_threshold)

    exact_match?(left, right) or hamming_distance(left.dhash, right.dhash) <= threshold
  end

  @spec hamming_distance(String.t(), String.t()) :: non_neg_integer()
  def hamming_distance(left, right) when is_binary(left) and is_binary(right) do
    left_integer = String.to_integer(left, 16)
    right_integer = String.to_integer(right, 16)

    left_integer
    |> Bitwise.bxor(right_integer)
    |> Integer.digits(2)
    |> Enum.sum()
  end

  defp exact_match?(left, right), do: left.exact_sha256 == right.exact_sha256

  defp sha256(bytes) do
    :sha256
    |> :crypto.hash(bytes)
    |> Base.encode16(case: :lower)
  end

  defp write_temp_image(bytes) do
    path = Path.join(System.tmp_dir!(), "instabot-fingerprint-#{System.unique_integer([:positive])}")

    case File.write(path, bytes) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, {:write_failed, reason}}
    end
  end

  defp image_dimensions(magick, path) do
    case System.cmd(magick, ["identify", "-format", "%w %h", path], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split()
        |> parse_dimensions()

      {output, _status} ->
        {:error, {:identify_failed, String.trim(output)}}
    end
  end

  defp parse_dimensions([width, height]) do
    {:ok, %{width: String.to_integer(width), height: String.to_integer(height)}}
  end

  defp parse_dimensions(_parts), do: {:error, :invalid_dimensions}

  defp image_dhash(magick, path) do
    case System.cmd(magick, [path, "-colorspace", "Gray", "-resize", "9x8!", "-depth", "8", "gray:-"],
           stderr_to_stdout: true
         ) do
      {pixels, 0} when byte_size(pixels) == 72 ->
        {:ok, dhash_from_pixels(pixels)}

      {output, _status} ->
        {:error, {:dhash_failed, String.trim(output)}}
    end
  end

  defp dhash_from_pixels(pixels) do
    pixels
    |> :binary.bin_to_list()
    |> Enum.chunk_every(9)
    |> Enum.flat_map(&row_bits/1)
    |> bits_to_hex()
  end

  defp row_bits(row) do
    row
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [left, right] -> if left > right, do: 1, else: 0 end)
  end

  defp bits_to_hex(bits) do
    bits
    |> Enum.reduce(0, fn bit, acc -> acc * 2 + bit end)
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(16, "0")
  end
end
