defmodule Instabot.Media.FingerprintTest do
  use ExUnit.Case, async: true

  alias Instabot.Media.Fingerprint

  @moduletag :tmp_dir

  if System.find_executable("magick") do
    test "exact same bytes match by sha256", %{tmp_dir: tmp_dir} do
      image_path = Path.join(tmp_dir, "same.png")
      {_output, 0} = System.cmd("magick", ["-size", "32x32", "xc:white", image_path])
      bytes = File.read!(image_path)

      assert {:ok, left} = Fingerprint.from_bytes(bytes)
      assert {:ok, right} = Fingerprint.from_bytes(bytes)
      assert left.exact_sha256 == right.exact_sha256
      assert Fingerprint.duplicate?(left, right)
    end

    test "resized recompressed copies match by dhash threshold", %{tmp_dir: tmp_dir} do
      original_path = Path.join(tmp_dir, "original.png")
      resized_path = Path.join(tmp_dir, "resized.jpg")
      {_output, 0} = System.cmd("magick", ["-size", "64x64", "gradient:black-white", original_path])
      {_output, 0} = System.cmd("magick", [original_path, "-resize", "128x128", "-quality", "80", resized_path])

      assert {:ok, original} = original_path |> File.read!() |> Fingerprint.from_bytes()
      assert {:ok, resized} = resized_path |> File.read!() |> Fingerprint.from_bytes()
      assert original.exact_sha256 != resized.exact_sha256
      assert Fingerprint.duplicate?(original, resized)
    end

    test "clearly different images do not match", %{tmp_dir: tmp_dir} do
      left_path = Path.join(tmp_dir, "left.png")
      right_path = Path.join(tmp_dir, "right.png")
      {_output, 0} = System.cmd("magick", ["-size", "64x64", "gradient:black-white", left_path])
      {_output, 0} = System.cmd("magick", ["-size", "64x64", "pattern:checkerboard", right_path])

      assert {:ok, left} = left_path |> File.read!() |> Fingerprint.from_bytes()
      assert {:ok, right} = right_path |> File.read!() |> Fingerprint.from_bytes()
      refute Fingerprint.duplicate?(left, right)
    end
  else
    test "ImageMagick is required for perceptual fingerprints" do
      assert {:error, :magick_not_installed} = Fingerprint.from_bytes("not an image")
    end
  end
end
