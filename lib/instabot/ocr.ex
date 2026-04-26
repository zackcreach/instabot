defmodule Instabot.OCR do
  @moduledoc """
  Tesseract OCR wrapper for extracting text from story screenshots.
  """

  @minimum_confidence 50.0
  @fallback_confidence 35.0
  @ignored_words ~w(instagram instagnam)

  @spec extract_text(String.t()) :: {:ok, String.t()} | {:error, term()}
  def extract_text(image_path) when is_binary(image_path) and image_path != "" do
    cond do
      not File.exists?(image_path) ->
        {:error, :file_not_found}

      not available?() ->
        {:error, :tesseract_not_installed}

      true ->
        run_tesseract(image_path)
    end
  end

  def extract_text(_image_path), do: {:error, :file_not_found}

  @spec available?() :: boolean()
  def available? do
    System.find_executable("tesseract") != nil
  end

  defp run_tesseract(image_path) do
    stderr_path = Path.join(System.tmp_dir!(), "instabot_tesseract_#{System.unique_integer([:positive])}.err")

    result =
      System.cmd("sh", [
        "-c",
        ~s(tesseract "$1" stdout --psm 11 tsv 2>"$2"),
        "tesseract",
        image_path,
        stderr_path
      ])

    stderr =
      case File.read(stderr_path) do
        {:ok, output} -> String.trim(output)
        {:error, _reason} -> ""
      end

    File.rm(stderr_path)

    case result do
      {tsv, 0} -> {:ok, extract_confident_text(tsv)}
      {output, status} -> {:error, {:ocr_failed, status, failure_output(output, stderr)}}
    end
  rescue
    error -> {:error, {:ocr_failed, Exception.message(error)}}
  end

  defp failure_output("", stderr), do: stderr
  defp failure_output(output, _stderr), do: String.trim(output)

  defp extract_confident_text(tsv) do
    tsv
    |> tsv_words()
    |> words_to_text(@minimum_confidence)
    |> fallback_text(tsv)
  end

  defp fallback_text("", tsv), do: tsv |> tsv_words() |> words_to_text(@fallback_confidence)
  defp fallback_text(text, _tsv), do: text

  defp tsv_words(tsv) do
    tsv
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> Enum.flat_map(&tsv_word/1)
  end

  defp tsv_word(line) do
    case String.split(line, "\t", parts: 12) do
      [
        _level,
        _page_number,
        block_number,
        paragraph_number,
        line_number,
        word_number,
        _left,
        _top,
        _width,
        _height,
        confidence,
        text
      ] ->
        [
          %{
            group: {integer(block_number), integer(paragraph_number), integer(line_number)},
            order: integer(word_number),
            confidence: float(confidence),
            text: String.trim(text)
          }
        ]

      _columns ->
        []
    end
  end

  defp words_to_text(words, minimum_confidence) do
    words
    |> Enum.filter(&visible_word?(&1, minimum_confidence))
    |> Enum.group_by(& &1.group)
    |> Enum.sort_by(fn {group, _words} -> group end)
    |> Enum.map_join("\n", fn {_group, line_words} ->
      line_words
      |> Enum.sort_by(& &1.order)
      |> Enum.map_join(" ", & &1.text)
      |> clean_line()
    end)
    |> String.trim()
  end

  defp visible_word?(%{text: ""}, _minimum_confidence), do: false

  defp visible_word?(%{confidence: confidence, text: text}, minimum_confidence) do
    not ignored_word?(text) and (confidence >= minimum_confidence or email?(text))
  end

  defp email?(text), do: String.match?(text, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)

  defp ignored_word?(text) do
    text
    |> String.downcase()
    |> then(&(&1 in @ignored_words))
  end

  defp clean_line(line) do
    line
    |> String.replace(~r/\s+([,.:;!?])/, "\\1")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp integer(value) do
    case Integer.parse(value) do
      {integer, _rest} -> integer
      :error -> 0
    end
  end

  defp float(value) do
    case Float.parse(value) do
      {float, _rest} -> float
      :error -> -1.0
    end
  end
end
