defmodule Instabot.Stories.AdClassifier do
  @moduledoc false

  @likely_ad_threshold 5
  @commerce_patterns [
    ~r/\bshop\s+now\b/i,
    ~r/\bnew\s+(colors?|collection|arrival|drop|drops)\b/i,
    ~r/\bavailable\s+now\b/i,
    ~r/\blimited\s+time\b/i,
    ~r/\bfree\s+shipping\b/i,
    ~r/\bdiscount\b/i,
    ~r/\bsale\b/i,
    ~r/\brestock(?:ed)?\b/i,
    ~r/\bbuy\s+now\b/i,
    ~r/\bpre[-\s]?order\b/i
  ]
  @sponsored_patterns [
    ~r/\bsponsored\b/i,
    ~r/\bpaid\s+partnership\b/i,
    ~r/\bad\b/i
  ]

  @spec classify(map()) :: map()
  def classify(attrs) do
    {score, reasons} =
      attrs
      |> chrome_score()
      |> add_text_score(text_value(attrs))

    score = max(score, 0)

    %{
      likely_ad: score >= @likely_ad_threshold,
      ad_score: score,
      ad_reasons: Enum.reverse(reasons)
    }
  end

  defp chrome_score(%{story_chrome_detected: false}), do: {5, ["missing_story_header"]}
  defp chrome_score(%{"story_chrome_detected" => false}), do: {5, ["missing_story_header"]}
  defp chrome_score(%{story_chrome_detected: true}), do: {0, []}
  defp chrome_score(%{"story_chrome_detected" => true}), do: {0, []}
  defp chrome_score(_attrs), do: {0, []}

  defp add_text_score({score, reasons}, text) when is_binary(text) and text != "" do
    {score, reasons}
    |> add_pattern_score(text, @sponsored_patterns, 6, "sponsored_text")
    |> add_pattern_score(text, @commerce_patterns, 3, "commerce_text")
  end

  defp add_text_score(result, _text), do: result

  defp add_pattern_score({score, reasons}, text, patterns, increment, reason) do
    if Enum.any?(patterns, &Regex.match?(&1, text)) do
      {score + increment, [reason | reasons]}
    else
      {score, reasons}
    end
  end

  defp text_value(attrs) do
    [
      Map.get(attrs, :ocr_text),
      Map.get(attrs, "ocr_text"),
      Map.get(attrs, :ad_text),
      Map.get(attrs, "ad_text")
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join("\n")
  end
end
