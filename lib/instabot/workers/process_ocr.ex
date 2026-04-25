defmodule Instabot.Workers.ProcessOCR do
  @moduledoc """
  Runs Tesseract OCR on a story screenshot and stores the extracted text.
  """

  use Oban.Worker, queue: :ocr, max_attempts: 2

  alias Instabot.Instagram
  alias Instabot.Notifications
  alias Instabot.OCR
  alias Instabot.Workers.SendImmediateNotification

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"story_id" => story_id}}) do
    story = Instagram.get_story!(story_id)

    case story.ocr_status do
      "pending" -> run_ocr(story)
      _already_processed -> notify_immediate_digest(story)
    end
  end

  defp run_ocr(story) do
    result =
      with {:ok, _story} <- Instagram.update_story_ocr(story, %{ocr_status: "processing"}),
           {:ok, text} <- OCR.extract_text(story.screenshot_path) do
        Instagram.update_story_ocr(story, %{ocr_text: text, ocr_status: "completed"})
        :ok
      else
        {:error, reason} ->
          Instagram.update_story_ocr(story, %{ocr_status: "failed"})
          {:error, reason}
      end

    notify_immediate_digest(story)
    result
  end

  defp notify_immediate_digest(story) do
    profile = Instagram.get_tracked_profile!(story.tracked_profile_id)

    case {Notifications.get_preference_for_user(profile.user_id), Instagram.count_stories_waiting_for_ocr(profile.id)} do
      {%{frequency: "immediate"}, 0} ->
        %{user_id: profile.user_id}
        |> SendImmediateNotification.new()
        |> Oban.insert()

        :ok

      _not_ready ->
        :ok
    end
  end
end
