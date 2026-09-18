defmodule Instabot.Media.StoryVideosTest do
  use Instabot.DataCase, async: false

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Media.Downloader
  alias Instabot.Media.StoryVideos
  alias Instabot.Repo

  @uploads_dir "test/tmp/story-videos"
  @video <<0, 0, 0, 24, "ftyp", "isom", 0, 0, 0, 0>>

  setup do
    previous_uploads_dir = Application.get_env(:instabot, :uploads_dir)
    previous_downloader = Application.get_env(:instabot, Downloader)
    previous_cutoff = Application.get_env(:instabot, :legacy_media_cutoff)
    File.rm_rf!(@uploads_dir)
    Application.put_env(:instabot, :uploads_dir, @uploads_dir)
    Application.delete_env(:instabot, :legacy_media_cutoff)

    adapter = fn request ->
      response = Req.Response.new(status: 200, headers: %{"content-type" => ["video/mp4"]}, body: @video)
      {request, response}
    end

    Application.put_env(:instabot, Downloader,
      resolver: fn _host -> {:ok, [{93, 184, 216, 34}]} end,
      request_options: [adapter: adapter]
    )

    on_exit(fn ->
      File.rm_rf!(@uploads_dir)
      restore_env(:uploads_dir, previous_uploads_dir)
      restore_env(Downloader, previous_downloader)
      restore_env(:legacy_media_cutoff, previous_cutoff)
    end)

    profile = tracked_profile_fixture(user_fixture())
    %{profile: profile}
  end

  test "backfills and verifies local story videos", %{profile: profile} do
    story =
      story_fixture(profile, %{
        story_type: "video",
        media_url: "https://media.example/story.mp4",
        media_path: nil
      })

    assert {:ok, %{migrated: 1, failures: []}} = StoryVideos.backfill()

    stored_story = Repo.get!(Instabot.Instagram.Story, story.id)
    assert @video == File.read!(stored_story.media_path)
    assert "video/mp4" == stored_story.media_content_type
    assert byte_size(@video) == stored_story.media_file_size
    assert {:ok, %{unchanged: 1, failures: []}} = StoryVideos.verify()
  end

  test "reports every missing video without stopping early", %{profile: profile} do
    _first = story_fixture(profile, %{story_type: "video", media_url: nil, media_path: nil})
    _second = story_fixture(profile, %{story_type: "video", media_url: nil, media_path: nil})

    assert {:error, %{records: 2, failures: failures}} = StoryVideos.backfill()
    assert 2 == length(failures)
  end

  defp restore_env(key, nil), do: Application.delete_env(:instabot, key)
  defp restore_env(key, value), do: Application.put_env(:instabot, key, value)
end
