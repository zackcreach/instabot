defmodule Instabot.Workers.ProcessOCR do
  @moduledoc """
  Runs Tesseract OCR on a story screenshot and stores the extracted text.
  """

  use Oban.Worker, queue: :ocr, max_attempts: 2

  alias Instabot.Instagram
  alias Instabot.OCR

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"story_id" => story_id}}) do
    story = Instagram.get_story!(story_id)

    case story.ocr_status do
      "pending" -> run_ocr(story)
      _already_processed -> :ok
    end
  end

  defp run_ocr(story) do
    with {:ok, _story} <- Instagram.update_story_ocr(story, %{ocr_status: "processing"}),
         {:ok, text} <- OCR.extract_text(story.screenshot_path) do
      Instagram.update_story_ocr(story, %{ocr_text: text, ocr_status: "completed"})
      :ok
    else
      {:error, reason} ->
        Instagram.update_story_ocr(story, %{ocr_status: "failed"})
        {:error, reason}
    end
  end
end
