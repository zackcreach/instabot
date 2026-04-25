defmodule Instabot.OCRTest do
  use ExUnit.Case, async: true

  alias Instabot.OCR

  describe "available?/0" do
    test "returns boolean based on tesseract availability" do
      assert is_boolean(OCR.available?())
    end
  end

  describe "extract_text/1" do
    test "returns error for non-existent file or missing tesseract" do
      result = OCR.extract_text("/nonexistent/path.png")
      assert {:error, reason} = result
      assert reason in [:file_not_found, :tesseract_not_installed]
    end

    @tag :external
    test "extracts text from a real image when tesseract is installed" do
      if OCR.available?() do
        path = Path.expand("../../test/support/fixtures/ocr_test.png", __DIR__)

        if File.exists?(path) do
          assert {:ok, text} = OCR.extract_text(path)
          assert is_binary(text)
        end
      end
    end
  end
end
