defmodule Instabot.Media.MigrationTest do
  use Instabot.DataCase, async: false

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Instagram
  alias Instabot.Instagram.PostImage
  alias Instabot.Media.Downloader
  alias Instabot.Media.Migration

  @uploads_dir "test/tmp/media-migration"

  setup do
    uploads_dir = Application.get_env(:instabot, :uploads_dir)
    downloader_config = Application.get_env(:instabot, Downloader)
    File.rm_rf!(@uploads_dir)
    Application.put_env(:instabot, :uploads_dir, @uploads_dir)

    on_exit(fn ->
      File.rm_rf!(@uploads_dir)
      restore_uploads_dir(uploads_dir)
      restore_downloader(downloader_config)
    end)
  end

  test "backfill is repeatable and verification rereads stored bytes" do
    bytes = <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46>>
    configure_download(bytes)
    user = user_fixture()
    profile = tracked_profile_fixture(user)
    post = post_fixture(profile)

    assert {:ok, post_image} =
             Instagram.create_post_image(post.id, %{
               original_url: "https://media.example/original.jpg",
               cloudinary_secure_url: "https://media.example/cloudinary.jpg",
               position: 0
             })

    assert {:ok, %{migrated: 1, failures: []}} = Migration.backfill()
    migrated_image = Repo.get!(PostImage, post_image.id)
    assert bytes == File.read!(migrated_image.local_path)
    assert Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == migrated_image.exact_sha256
    assert byte_size(bytes) == migrated_image.file_size

    assert {:ok, %{unchanged: 1, failures: []}} = Migration.backfill()
    assert {:ok, %{verified: 1, failures: []}} = Migration.verify()
  end

  test "inventory processes every record before reporting missing sources" do
    user = user_fixture()
    profile = tracked_profile_fixture(user)
    _story = story_fixture(profile, %{screenshot_path: Path.join(@uploads_dir, "missing.jpg"), media_url: nil})

    assert {:error, report} = Migration.inventory()
    assert 1 == report.records
    assert 1 == length(report.failures)
    assert ":source_missing" == report.failures |> List.first() |> Map.fetch!(:reason)
  end

  defp configure_download(bytes) do
    adapter = fn request ->
      {request, Req.Response.new(status: 200, headers: %{"content-type" => ["image/jpeg"]}, body: bytes)}
    end

    Application.put_env(:instabot, Downloader,
      resolver: fn _host -> {:ok, [{93, 184, 216, 34}]} end,
      request_options: [adapter: adapter]
    )
  end

  defp restore_uploads_dir(nil), do: Application.delete_env(:instabot, :uploads_dir)
  defp restore_uploads_dir(value), do: Application.put_env(:instabot, :uploads_dir, value)
  defp restore_downloader(nil), do: Application.delete_env(:instabot, Downloader)
  defp restore_downloader(value), do: Application.put_env(:instabot, Downloader, value)
end
