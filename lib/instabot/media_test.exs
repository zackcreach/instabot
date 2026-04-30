defmodule Instabot.MediaTest do
  use ExUnit.Case, async: true

  alias Instabot.Media
  alias Instabot.Media.Cloudinary

  @test_uploads_dir "test/tmp/uploads"

  setup do
    media_config = Application.get_env(:instabot, Media)
    cloudinary_config = Application.get_env(:instabot, Cloudinary)

    File.rm_rf!(@test_uploads_dir)
    Application.put_env(:instabot, :uploads_dir, @test_uploads_dir)

    on_exit(fn ->
      File.rm_rf!(@test_uploads_dir)
      Application.delete_env(:instabot, :uploads_dir)
      restore_env(Media, media_config)
      restore_env(Cloudinary, cloudinary_config)
    end)
  end

  describe "uploads_dir/0" do
    test "returns configured directory" do
      assert @test_uploads_dir == Media.uploads_dir()
    end

    test "returns default when not configured" do
      Application.delete_env(:instabot, :uploads_dir)
      assert "priv/static/uploads" == Media.uploads_dir()
    end
  end

  describe "ensure_directory/1" do
    test "creates nested directory structure" do
      path = Path.join(@test_uploads_dir, "deep/nested/dir")
      assert :ok == Media.ensure_directory(path)
      assert File.dir?(path)
    end

    test "succeeds when directory already exists" do
      File.mkdir_p!(@test_uploads_dir)
      assert :ok == Media.ensure_directory(@test_uploads_dir)
    end
  end

  describe "delete_file/1" do
    test "deletes existing file" do
      File.mkdir_p!(@test_uploads_dir)
      path = Path.join(@test_uploads_dir, "deleteme.txt")
      File.write!(path, "test")
      assert :ok == Media.delete_file(path)
      refute File.exists?(path)
    end

    test "returns :ok for non-existent file" do
      assert :ok == Media.delete_file(Path.join(@test_uploads_dir, "nonexistent.txt"))
    end
  end

  describe "download_and_save/3" do
    test "downloads and saves file from URL" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/image.jpg", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/jpeg")
        |> Plug.Conn.resp(200, <<0xFF, 0xD8, 0xFF, 0xE0>>)
      end)

      url = "http://localhost:#{bypass.port}/image.jpg"
      assert {:ok, result} = Media.download_and_save(url, "test_post", "image_0.jpg")
      assert %{local_path: local_path, content_type: "image/jpeg", file_size: 4} = result
      assert String.ends_with?(local_path, "test_post/image_0.jpg")
      assert File.exists?(local_path)
    end

    test "returns error for non-200 response" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/missing.jpg", fn conn ->
        Plug.Conn.resp(conn, 404, "Not Found")
      end)

      url = "http://localhost:#{bypass.port}/missing.jpg"
      assert {:error, {:http_error, 404}} = Media.download_and_save(url, "test_post", "image_0.jpg")
    end

    test "infers content type from URL extension when header missing" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/photo.png", fn conn ->
        Plug.Conn.resp(conn, 200, <<0x89, 0x50, 0x4E, 0x47>>)
      end)

      url = "http://localhost:#{bypass.port}/photo.png"
      assert {:ok, %{content_type: "image/png"}} = Media.download_and_save(url, "test_post", "image_0.png")
    end
  end

  describe "download_and_upload/3" do
    test "downloads bytes and sends them to the configured storage adapter" do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/image.jpg", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/jpeg")
        |> Plug.Conn.resp(200, <<0xFF, 0xD8, 0xFF, 0xE0>>)
      end)

      url = "http://localhost:#{bypass.port}/image.jpg"
      assert {:ok, result} = Media.download_and_upload(url, "test_post", "image_0.jpg")

      assert %{
               original_url: ^url,
               local_path: local_path,
               content_type: "image/jpeg",
               file_size: 4
             } = result

      assert String.ends_with?(local_path, "test_post/image_0.jpg")
      assert File.exists?(local_path)
    end
  end

  describe "post_image_urls/1" do
    test "prefers sorted stored post images over scraped media URLs" do
      post = %{
        media_urls: ["https://example.com/fallback.jpg"],
        post_images: [
          %{
            position: 1,
            local_path: "priv/static/uploads/posts/local.jpg",
            cloudinary_secure_url: nil
          },
          %{
            position: 0,
            local_path: "priv/static/uploads/posts/old.jpg",
            cloudinary_secure_url: "https://res.cloudinary.com/demo/image/upload/v1/posts/hosted.jpg"
          }
        ]
      }

      assert [
               "https://res.cloudinary.com/demo/image/upload/v1/posts/hosted.jpg",
               "/uploads/posts/local.jpg"
             ] == Media.post_image_urls(post)
    end

    test "falls back to scraped media URLs when stored post images have no usable URL" do
      post = %{
        media_urls: ["https://example.com/fallback.jpg"],
        post_images: [%{position: 0, local_path: nil, cloudinary_secure_url: nil}]
      }

      assert ["https://example.com/fallback.jpg"] == Media.post_image_urls(post)
    end
  end

  describe "story_preview_url/2" do
    test "prefers Cloudinary story screenshots over local screenshots and scraped media URLs" do
      story = %{
        screenshot_url: "https://res.cloudinary.com/demo/image/upload/v1/stories/story.jpg",
        screenshot_path: "priv/static/screenshots/story.png",
        media_url: "https://example.com/story.jpg"
      }

      assert "https://res.cloudinary.com/demo/image/upload/v1/stories/story.jpg" == Media.story_preview_url(story)
    end

    test "falls back to a browser-loadable scraped media URL when required local screenshot is missing" do
      story = %{
        screenshot_url: nil,
        screenshot_path: "priv/static/screenshots/missing-story.png",
        media_url: "https://example.com/story.jpg"
      }

      assert "https://example.com/story.jpg" == Media.story_preview_url(story, require_local_exists: true)
    end

    test "blocks configured scraped media hosts" do
      story = %{
        screenshot_url: nil,
        screenshot_path: "priv/static/screenshots/missing-story.png",
        media_url: "https://scontent-atl3-1.cdninstagram.com/story.jpg"
      }

      assert is_nil(Media.story_preview_url(story, require_local_exists: true, blocked_hosts: ["cdninstagram.com"]))
    end
  end

  defp restore_env(Media, nil), do: Application.delete_env(:instabot, Media)

  defp restore_env(Cloudinary, nil), do: Application.delete_env(:instabot, Cloudinary)

  defp restore_env(Media, value), do: Application.put_env(:instabot, Media, value)

  defp restore_env(Cloudinary, value), do: Application.put_env(:instabot, Cloudinary, value)
end
