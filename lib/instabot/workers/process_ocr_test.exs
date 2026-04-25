defmodule Instabot.Workers.ProcessOCRTest do
  use Instabot.DataCase, async: true

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Instagram
  alias Instabot.Workers.ProcessOCR

  setup do
    user = user_fixture()
    profile = tracked_profile_fixture(user)

    {:ok, story} =
      Instagram.create_story(profile.id, %{
        instagram_story_id: "story_#{System.unique_integer([:positive])}",
        story_type: "image",
        screenshot_path: "/tmp/test_screenshot.png",
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
      result = ProcessOCR.perform(%Oban.Job{args: %{"story_id" => story.id}})
      assert {:error, reason} = result
      assert reason in [:file_not_found, :tesseract_not_installed]

      refreshed = Instagram.get_story!(story.id)
      assert "failed" == refreshed.ocr_status
    end

    test "sets status to failed when tesseract is not installed", %{story: story} do
      File.mkdir_p!("/tmp")
      File.write!("/tmp/test_screenshot.png", <<0x89, 0x50, 0x4E, 0x47>>)

      result = ProcessOCR.perform(%Oban.Job{args: %{"story_id" => story.id}})

      refreshed = Instagram.get_story!(story.id)

      if Instabot.OCR.available?() do
        assert refreshed.ocr_status in ["completed", "failed"]
      else
        assert {:error, :tesseract_not_installed} == result
        assert "failed" == refreshed.ocr_status
      end

      File.rm("/tmp/test_screenshot.png")
    end
  end
end
