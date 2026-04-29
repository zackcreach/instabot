defmodule Instabot.OCR do
  @moduledoc """
  Tesseract OCR wrapper for extracting text from story screenshots.
  """

  @primary_confidence 60.0
  @supporting_confidence 25.0
  @ignored_words ~w(instagram instagnam)

  @spec extract_text(String.t()) :: {:ok, String.t()} | {:error, term()}
  def extract_text(image_path) when is_binary(image_path) and image_path != "" do
    cond do
      not File.exists?(image_path) ->
        {:error, :file_not_found}

      not available?() ->
        {:error, :tesseract_not_installed}

      true ->
        extract_text_from_variants(image_path)
    end
  end

  def extract_text(_image_path), do: {:error, :file_not_found}

  @spec available?() :: boolean()
  def available? do
    System.find_executable("tesseract") != nil
  end

  defp extract_text_from_variants(image_path) do
    variants = image_variants(image_path)

    results =
      Enum.map(variants, fn variant ->
        {variant, run_tesseract(variant)}
      end)

    Enum.each(variants, &cleanup_variant/1)

    case successful_text(results) do
      "" -> first_error(results)
      text -> {:ok, text}
    end
  end

  defp run_tesseract(%{path: image_path, page_segmentation_mode: page_segmentation_mode}) do
    stderr_path = Path.join(System.tmp_dir!(), "instabot_tesseract_#{System.unique_integer([:positive])}.err")

    result =
      System.cmd("sh", [
        "-c",
        ~s(tesseract "$1" stdout --psm "$2" tsv 2>"$3"),
        "tesseract",
        image_path,
        page_segmentation_mode,
        stderr_path
      ])

    stderr =
      case File.read(stderr_path) do
        {:ok, output} -> String.trim(output)
        {:error, _reason} -> ""
      end

    File.rm(stderr_path)

    case result do
      {tsv, 0} -> {:ok, extract_confident_lines(tsv)}
      {output, status} -> {:error, {:ocr_failed, status, failure_output(output, stderr)}}
    end
  rescue
    error -> {:error, {:ocr_failed, Exception.message(error)}}
  end

  defp failure_output("", stderr), do: stderr
  defp failure_output(output, _stderr), do: String.trim(output)

  defp successful_text(results) do
    results
    |> Enum.flat_map(fn
      {_variant, {:ok, lines}} -> lines
      {_variant, {:error, _reason}} -> []
    end)
    |> Enum.map(&clean_line/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> merge_similar_lines()
    |> Enum.join("\n")
    |> String.trim()
  end

  defp first_error(results) do
    case Enum.find(results, fn {_variant, result} -> match?({:error, _reason}, result) end) do
      {_variant, {:error, reason}} -> {:error, reason}
      nil -> {:ok, ""}
    end
  end

  defp image_variants(image_path) do
    original = %{path: image_path, page_segmentation_mode: "11", temporary?: false}

    case preprocessed_story_crop(image_path) do
      {:ok, path} ->
        [
          original,
          %{path: path, page_segmentation_mode: "6", temporary?: true},
          %{path: path, page_segmentation_mode: "11", temporary?: true}
        ]

      {:error, _reason} ->
        [original]
    end
  end

  defp cleanup_variant(%{temporary?: true, path: path}), do: File.rm(path)
  defp cleanup_variant(_variant), do: :ok

  defp preprocessed_story_crop(image_path) do
    with magick when is_binary(magick) <- System.find_executable("magick"),
         {:ok, {width, height}} <- image_dimensions(magick, image_path),
         {:ok, output_path} <- temporary_image_path(image_path) do
      geometry = story_crop_geometry(width, height)

      case System.cmd(magick, [
             image_path,
             "-crop",
             geometry,
             "-colorspace",
             "Gray",
             "-resize",
             "200%",
             "-sharpen",
             "0x1",
             output_path
           ]) do
        {_output, 0} -> {:ok, output_path}
        {output, _status} -> {:error, output}
      end
    else
      _reason -> {:error, :preprocessing_unavailable}
    end
  end

  defp image_dimensions(magick, image_path) do
    case System.cmd(magick, ["identify", "-format", "%w %h", image_path], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split(" ", trim: true)
        |> dimensions()

      {output, _status} ->
        {:error, output}
    end
  end

  defp dimensions([width, height]) do
    with {parsed_width, ""} <- Integer.parse(width),
         {parsed_height, ""} <- Integer.parse(height) do
      {:ok, {parsed_width, parsed_height}}
    else
      _reason -> {:error, :invalid_dimensions}
    end
  end

  defp dimensions(_parts), do: {:error, :invalid_dimensions}

  defp story_crop_geometry(width, height) when width > height do
    crop_height = max(height - 30, 1)
    crop_width = min(width, round(crop_height * 9 / 16))
    crop_left = max(div(width - crop_width, 2), 0)
    crop_top = max(div(height - crop_height, 2), 0)

    "#{crop_width}x#{crop_height}+#{crop_left}+#{crop_top}"
  end

  defp story_crop_geometry(width, height), do: "#{width}x#{height}+0+0"

  defp temporary_image_path(image_path) do
    directory = Path.dirname(image_path)
    basename = Path.basename(image_path, Path.extname(image_path))
    path = Path.join(directory, "#{basename}.ocr-#{System.unique_integer([:positive])}.png")

    case File.touch(path) do
      :ok ->
        File.rm(path)
        {:ok, path}

      {:error, reason} ->
        {:error, reason}
    end
  end

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

  defp extract_confident_lines(tsv) do
    tsv
    |> tsv_words()
    |> Enum.group_by(& &1.group)
    |> Enum.sort_by(fn {group, _words} -> group end)
    |> Enum.flat_map(fn {_group, words} -> confident_line(words) end)
  end

  defp confident_line(words) do
    words
    |> Enum.sort_by(& &1.order)
    |> Enum.filter(&meaningful_visible_word?/1)
    |> line_text()
  end

  defp line_text([]), do: []

  defp line_text([_word] = words) do
    words
    |> Enum.filter(&visible_single_word?/1)
    |> Enum.map_join(" ", & &1.text)
    |> clean_line()
    |> line_result()
  end

  defp line_text(words) do
    primary_count = Enum.count(words, &primary_word?/1)
    supporting_count = Enum.count(words, &supporting_word?/1)

    words
    |> Enum.filter(&visible_word?(&1, primary_count, supporting_count))
    |> Enum.map_join(" ", & &1.text)
    |> clean_line()
    |> line_result()
  end

  defp line_result(""), do: []
  defp line_result(line), do: [line]

  defp meaningful_visible_word?(%{text: text}) do
    meaningful_word?(text) and not ignored_word?(text)
  end

  defp visible_word?(%{text: text}, _primary_count, _supporting_count) when text in ["-", "_", "|"], do: false
  defp visible_word?(word, _primary_count, _supporting_count) when is_binary(word.text) and word.text == "", do: false

  defp visible_word?(word, _primary_count, _supporting_count) when word.confidence >= @primary_confidence do
    not long_uppercase_token?(word.text)
  end

  defp visible_word?(word, primary_count, supporting_count) do
    email?(word.text) or
      (primary_count >= 2 and supporting_word?(word)) or
      (primary_count >= 1 and supporting_count >= 3 and supporting_word?(word))
  end

  defp visible_single_word?(word) do
    (email?(word.text) or word.confidence >= @primary_confidence) and not long_uppercase_token?(word.text)
  end

  defp primary_word?(%{confidence: confidence}), do: confidence >= @primary_confidence
  defp supporting_word?(%{confidence: confidence}), do: confidence >= @supporting_confidence

  defp email?(text), do: String.match?(text, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)

  defp meaningful_word?(text) do
    email?(text) or (String.match?(text, ~r/[[:alnum:]]/u) and String.length(alphanumeric_text(text)) > 1)
  end

  defp ignored_word?(text) do
    text
    |> String.downcase()
    |> Kernel.in(@ignored_words)
  end

  defp alphanumeric_text(text), do: String.replace(text, ~r/[^[:alnum:]]/u, "")

  defp long_uppercase_token?(text) do
    alphanumeric = alphanumeric_text(text)

    String.length(alphanumeric) > 12 and String.upcase(alphanumeric) == alphanumeric
  end

  defp clean_line(line) do
    line
    |> String.replace(~r/\s+([,.:;!?])/, "\\1")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp merge_similar_lines(lines), do: Enum.reduce(lines, [], &merge_line/2)

  defp merge_line(line, []), do: [line]

  defp merge_line(line, lines) do
    case merge_line_at(line, lines, []) do
      {:merged, merged_lines} -> merged_lines
      :new_line -> lines ++ [line]
    end
  end

  defp merge_line_at(line, [existing | rest], previous) do
    case merged_line(line, existing) do
      {:ok, merged} -> {:merged, previous ++ [merged | rest]}
      :error -> merge_line_at(line, rest, previous ++ [existing])
    end
  end

  defp merge_line_at(_line, [], _previous), do: :new_line

  defp merged_line(line, existing) do
    line_tokens = String.split(line, " ", trim: true)
    existing_tokens = String.split(existing, " ", trim: true)

    cond do
      contained_tokens?(line_tokens, existing_tokens) ->
        {:ok, existing}

      contained_tokens?(existing_tokens, line_tokens) ->
        {:ok, line}

      true ->
        merge_overlapping_tokens(line_tokens, existing_tokens)
    end
  end

  defp contained_tokens?(tokens, other_tokens) do
    normalized_tokens = Enum.map(tokens, &normalized_token/1)
    normalized_other_tokens = Enum.map(other_tokens, &normalized_token/1)

    normalized_tokens != [] and Enum.all?(normalized_tokens, &(&1 in normalized_other_tokens))
  end

  defp merge_overlapping_tokens(tokens, other_tokens) do
    token_count = min(length(tokens), length(other_tokens))

    case token_count do
      count when count >= 2 ->
        Enum.find_value(count..2//-1, :error, fn count ->
          merge_overlapping_tokens(tokens, other_tokens, count)
        end)

      _count ->
        :error
    end
  end

  defp merge_overlapping_tokens(tokens, other_tokens, count) do
    cond do
      same_tokens?(Enum.take(tokens, -count), Enum.take(other_tokens, count)) ->
        {:ok, Enum.join(tokens ++ Enum.drop(other_tokens, count), " ")}

      same_tokens?(Enum.take(other_tokens, -count), Enum.take(tokens, count)) ->
        {:ok, Enum.join(other_tokens ++ Enum.drop(tokens, count), " ")}

      true ->
        nil
    end
  end

  defp same_tokens?(tokens, other_tokens) do
    Enum.map(tokens, &normalized_token/1) == Enum.map(other_tokens, &normalized_token/1)
  end

  defp normalized_token(token), do: token |> String.downcase() |> alphanumeric_text()

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
