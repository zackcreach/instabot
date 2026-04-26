defmodule Instabot.Workers.ProcessOCRTest do
  use Instabot.DataCase, async: true
  use Oban.Testing, repo: Instabot.Repo

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Instagram
  alias Instabot.Notifications
  alias Instabot.Workers.ProcessOCR
  alias Instabot.Workers.SendImmediateNotification

  setup do
    user = user_fixture()
    profile = tracked_profile_fixture(user)
    screenshot_path = Path.join(System.tmp_dir!(), "process_ocr_#{System.unique_integer([:positive])}.png")

    on_exit(fn -> File.rm(screenshot_path) end)

    {:ok, story} =
      Instagram.create_story(profile.id, %{
        instagram_story_id: "story_#{System.unique_integer([:positive])}",
        story_type: "image",
        screenshot_path: screenshot_path,
        ocr_status: "pending"
      })

    %{story: story, profile: profile}
  end

  describe "perform/1" do
    test "skips stories that are already processed", %{story: story} do
      {:ok, story} = Instagram.update_story_ocr(story, %{ocr_status: "completed", ocr_text: "existing"})

      assert :ok ==
               ProcessOCR.perform(%Oban.Job{args: %{"story_id" => story.id}})

      refreshed = Instagram.get_story!(story.id)
      assert "existing" == refreshed.ocr_text
      assert "completed" == refreshed.ocr_status
    end

    test "sets status to failed when OCR cannot process", %{story: story} do
      assert :ok == ProcessOCR.perform(%Oban.Job{args: %{"story_id" => story.id}})

      refreshed = Instagram.get_story!(story.id)
      assert "failed" == refreshed.ocr_status
    end

    test "enqueues immediate notification after terminal OCR result", %{story: story, profile: profile} do
      preference = Notifications.get_or_create_preference(profile.user_id)
      {:ok, _preference} = Notifications.update_preference(preference, %{frequency: "immediate"})

      assert :ok == ProcessOCR.perform(%Oban.Job{args: %{"story_id" => story.id}})

      assert_enqueued(worker: SendImmediateNotification, args: %{user_id: profile.user_id})
    end

    test "does not enqueue immediate notification while another story is waiting for OCR", %{
      story: story,
      profile: profile
    } do
      preference = Notifications.get_or_create_preference(profile.user_id)
      {:ok, _preference} = Notifications.update_preference(preference, %{frequency: "immediate"})

      {:ok, _other_story} =
        Instagram.create_story(profile.id, %{
          instagram_story_id: "other_pending_#{System.unique_integer([:positive])}",
          story_type: "image",
          screenshot_path: "/tmp/other_pending_ocr.png",
          ocr_status: "pending"
        })

      assert :ok == ProcessOCR.perform(%Oban.Job{args: %{"story_id" => story.id}})

      refute_enqueued(worker: SendImmediateNotification, args: %{user_id: profile.user_id})
    end

    test "leaves OCR pending when tesseract is not installed", %{story: story} do
      File.write!(story.screenshot_path, <<0x89, 0x50, 0x4E, 0x47>>)

      result = ProcessOCR.perform(%Oban.Job{args: %{"story_id" => story.id}})

      refreshed = Instagram.get_story!(story.id)

      if Instabot.OCR.available?() do
        assert refreshed.ocr_status in ["completed", "failed"]
      else
        assert {:error, :tesseract_not_installed} == result
        assert "pending" == refreshed.ocr_status
      end
    end
  end
end
