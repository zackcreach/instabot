defmodule Instabot.Workers.DownloadImageTest do
  use Instabot.DataCase, async: false

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Instagram
  alias Instabot.Workers.DownloadImage

  @test_uploads_dir "test/tmp/uploads_worker"

  setup do
    File.rm_rf!(@test_uploads_dir)
    Application.put_env(:instabot, :uploads_dir, @test_uploads_dir)

    on_exit(fn ->
      File.rm_rf!(@test_uploads_dir)
      Application.delete_env(:instabot, :uploads_dir)
    end)

    user = user_fixture()
    profile = tracked_profile_fixture(user)

    {:ok, post} =
      Instagram.create_post(profile.id, %{
        instagram_post_id: "post_#{System.unique_integer([:positive])}",
        post_type: "image",
        media_urls: ["http://example.com/image.jpg"]
      })

    %{user: user, profile: profile, post: post}
  end

  describe "perform/1" do
    test "downloads image and creates post_image record", %{post: post} do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/photo.jpg", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/jpeg")
        |> Plug.Conn.resp(200, <<0xFF, 0xD8, 0xFF, 0xE0>>)
      end)

      url = "http://localhost:#{bypass.port}/photo.jpg"

      assert :ok ==
               DownloadImage.perform(%Oban.Job{
                 args: %{"post_id" => post.id, "url" => url, "position" => 0}
               })

      post_with_images = Repo.preload(post, :post_images)
      assert [post_image] = post_with_images.post_images
      assert post_image.original_url == url
      assert post_image.position == 0
      assert post_image.content_type == "image/jpeg"
      assert 4 == post_image.file_size
      assert File.exists?(post_image.local_path)
    end

    test "returns error on HTTP failure", %{post: post} do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/missing.jpg", fn conn ->
        Plug.Conn.resp(conn, 404, "Not Found")
      end)

      url = "http://localhost:#{bypass.port}/missing.jpg"

      assert {:error, {:http_error, 404}} ==
               DownloadImage.perform(%Oban.Job{
                 args: %{"post_id" => post.id, "url" => url, "position" => 0}
               })
    end

    test "defaults to .jpg extension for extensionless URLs", %{post: post} do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/media/12345", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/jpeg")
        |> Plug.Conn.resp(200, <<0xFF, 0xD8>>)
      end)

      url = "http://localhost:#{bypass.port}/media/12345"

      assert :ok ==
               DownloadImage.perform(%Oban.Job{
                 args: %{"post_id" => post.id, "url" => url, "position" => 2}
               })

      post_with_images = Repo.preload(post, :post_images)
      assert [image] = post_with_images.post_images
      assert String.ends_with?(image.local_path, "image_2.jpg")
    end
  end
end
