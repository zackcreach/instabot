defmodule Instabot.Workers.ProcessOCR do
  @moduledoc """
  Runs Tesseract OCR on a story screenshot and stores the extracted text.
  """

  use Oban.Worker, queue: :ocr, max_attempts: 2

  alias Instabot.Instagram
  alias Instabot.Media
  alias Instabot.Notifications
  alias Instabot.OCR
  alias Instabot.Workers.SendImmediateNotification

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"story_id" => story_id}}) do
    story = Instagram.get_story!(story_id)

    case story.ocr_status do
      status when status in ["pending", "failed"] -> run_ocr(story)
      _already_processed -> notify_immediate_digest(story)
    end
  end

  defp run_ocr(story) do
    result =
      with {:ok, processing_story} <- Instagram.update_story_ocr(story, %{ocr_status: "processing"}),
           {:ok, image_path, temporary?} <- ocr_image_path(story),
           {:ok, text} <- extract_text(image_path, temporary?) do
        Instagram.update_story_ocr(processing_story, %{ocr_text: text, ocr_status: "completed"})
        :ok
      else
        {:error, :tesseract_not_installed} = error ->
          story.id
          |> Instagram.get_story!()
          |> Instagram.update_story_ocr(%{ocr_status: "pending"})

          Logger.warning("OCR unavailable for story #{story.id}: :tesseract_not_installed")
          error

        {:error, reason} ->
          story.id
          |> Instagram.get_story!()
          |> Instagram.update_story_ocr(%{ocr_status: "failed"})

          Logger.warning("OCR failed for story #{story.id}: #{inspect(reason)}")
          :ok
      end

    notify_immediate_digest(story)
    result
  end

  defp ocr_image_path(%{screenshot_url: url}) when is_binary(url) and url != "" do
    with {:ok, path} <- Media.download_to_temp(url) do
      {:ok, path, true}
    end
  end

  defp ocr_image_path(%{screenshot_path: path}) when is_binary(path) and path != "" do
    {:ok, path, false}
  end

  defp ocr_image_path(_story), do: {:error, :file_not_found}

  defp extract_text(image_path, true) do
    OCR.extract_text(image_path)
  after
    Media.delete_file(image_path)
  end

  defp extract_text(image_path, false), do: OCR.extract_text(image_path)

  defp notify_immediate_digest(story) do
    profile = Instagram.get_tracked_profile!(story.tracked_profile_id)

    case {Notifications.effective_profile_preference(profile.user_id, profile.id),
          Instagram.count_stories_waiting_for_ocr(profile.id)} do
      {%{frequency: "immediate"}, 0} ->
        %{user_id: profile.user_id, tracked_profile_id: profile.id}
        |> SendImmediateNotification.new()
        |> Oban.insert()

        :ok

      _not_ready ->
        :ok
    end
  end
end
