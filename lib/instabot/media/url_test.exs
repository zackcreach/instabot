defmodule Instabot.Media.UrlTest do
  use ExUnit.Case, async: false

  alias Instabot.Media.Url

  setup do
    original_imgproxy = Application.get_all_env(:imgproxy)
    original_base_url = Application.get_env(:instabot, :media_base_url)

    Application.put_all_env(
      imgproxy: [
        prefix: "https://images.prominent.tools/transform",
        key: String.duplicate("01", 32),
        salt: String.duplicate("02", 32)
      ],
      instabot: [media_base_url: "https://images.prominent.tools"]
    )

    on_exit(fn ->
      Application.put_all_env(imgproxy: original_imgproxy, instabot: [media_base_url: original_base_url])
    end)

    :ok
  end

  test "builds signed bounded variants and changes the URL with the version" do
    first = Url.feed_thumbnail_url("ab/example image.jpg", "one")
    second = Url.feed_thumbnail_url("ab/example image.jpg", "two")

    assert "https://images.prominent.tools/transform/iyF_IdSJ4sI7fTOE_d-_-5SYhHJsvq9l2v_5NF_gPlU/cachebuster:one/quality:78/rs:fill:360:360:false/bG9jYWw6Ly8vaW5zdGFib3QvYWIvZXhhbXBsZSUyMGltYWdlLmpwZw.webp" ==
             first

    refute String.contains?(first, "/insecure/")
    refute first == second
  end

  test "encodes original paths" do
    assert "https://images.prominent.tools/original/instabot/ab/example%20image.jpg" ==
             Url.original_url("ab/example image.jpg")
  end

  test "rejects excessive dimensions and unsupported formats" do
    assert_raise ArgumentError, fn ->
      Url.variant_url("image.jpg", width: 1601, height: 1, fit: :fit, quality: 80, format: :webp, version: "one")
    end

    assert_raise ArgumentError, fn ->
      Url.variant_url("image.jpg", width: 1, height: 1, fit: :fit, quality: 80, format: :gif, version: "one")
    end

    assert_raise ArgumentError, fn -> Url.original_url("../secret.jpg") end
    assert_raise ArgumentError, fn -> Url.original_url("/etc/passwd") end
  end
end
