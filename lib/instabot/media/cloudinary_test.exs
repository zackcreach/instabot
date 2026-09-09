defmodule Instabot.Media.CloudinaryTest do
  use ExUnit.Case, async: false

  alias Instabot.Media.Cloudinary

  setup {Req.Test, :verify_on_exit!}

  setup do
    previous_config = Application.get_env(:instabot, Cloudinary)

    Application.put_env(:instabot, Cloudinary,
      cloud_name: "demo",
      api_key: "key",
      api_secret: "secret",
      folder: "instabot/test",
      endpoint: "https://cloudinary.example",
      request_options: [plug: {Req.Test, Cloudinary}]
    )

    on_exit(fn ->
      restore_config(previous_config)
    end)

    :ok
  end

  describe "upload_image/2" do
    test "uploads bytes with basic auth and normalizes response" do
      Req.Test.expect(Cloudinary, fn conn ->
        assert "POST" == conn.method
        assert "/demo/image/upload" == conn.request_path
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert ["Basic " <> encoded] = Plug.Conn.get_req_header(conn, "authorization")
        assert "key:secret" == Base.decode64!(encoded)
        assert body =~ "image-bytes"
        assert body =~ "public_id"
        assert body =~ "posts/post_id/image_0"
        assert body =~ "instabot/test"

        Plug.Conn.resp(
          conn,
          200,
          Jason.encode!(%{
            public_id: "instabot/test/posts/post_id/image_0",
            secure_url: "https://res.cloudinary.com/demo/image/upload/v1/posts/post_id/image_0.jpg",
            version: 1_234,
            format: "jpg",
            resource_type: "image",
            bytes: 11,
            width: 640,
            height: 480
          })
        )
      end)

      assert {:ok, metadata} =
               Cloudinary.upload_image("image-bytes",
                 filename: "image_0.jpg",
                 content_type: "image/jpeg",
                 public_id: "posts/post_id/image_0"
               )

      assert %{
               cloudinary_public_id: "instabot/test/posts/post_id/image_0",
               cloudinary_secure_url: "https://res.cloudinary.com/demo/image/upload/v1/posts/post_id/image_0.jpg",
               cloudinary_version: "1234",
               cloudinary_format: "jpg",
               cloudinary_resource_type: "image",
               file_size: 11,
               width: 640,
               height: 480
             } == metadata
    end

    test "returns an error tuple for non-success responses" do
      Req.Test.expect(Cloudinary, fn conn ->
        assert "POST" == conn.method
        assert "/demo/image/upload" == conn.request_path
        Plug.Conn.resp(conn, 401, Jason.encode!(%{error: %{message: "bad credentials"}}))
      end)

      assert {:error, {:http_error, 401, %{"error" => %{"message" => "bad credentials"}}}} =
               Cloudinary.upload_image("image-bytes",
                 filename: "image_0.jpg",
                 content_type: "image/jpeg",
                 public_id: "posts/post_id/image_0"
               )
    end
  end

  defp restore_config(nil), do: Application.delete_env(:instabot, Cloudinary)
  defp restore_config(config), do: Application.put_env(:instabot, Cloudinary, config)
end
