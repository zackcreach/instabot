defmodule Instabot.MediaTest do
  use ExUnit.Case, async: true

  alias Instabot.Media

  @test_uploads_dir "test/tmp/uploads"

  setup do
    File.rm_rf!(@test_uploads_dir)
    Application.put_env(:instabot, :uploads_dir, @test_uploads_dir)

    on_exit(fn ->
      File.rm_rf!(@test_uploads_dir)
      Application.delete_env(:instabot, :uploads_dir)
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
end
