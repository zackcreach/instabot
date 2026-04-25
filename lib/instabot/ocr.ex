defmodule Instabot.OCR do
  @moduledoc """
  Tesseract OCR wrapper for extracting text from story screenshots.
  """

  @spec extract_text(String.t()) :: {:ok, String.t()} | {:error, term()}
  def extract_text(image_path) do
    cond do
      not available?() ->
        {:error, :tesseract_not_installed}

      not File.exists?(image_path) ->
        {:error, :file_not_found}

      true ->
        try do
          text = TesseractOcr.read(image_path)
          {:ok, String.trim(text)}
        rescue
          error -> {:error, {:ocr_failed, Exception.message(error)}}
        end
    end
  end

  @spec available?() :: boolean()
  def available? do
    System.find_executable("tesseract") != nil
  end
end
