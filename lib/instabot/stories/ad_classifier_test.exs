defmodule Instabot.Stories.AdClassifierTest do
  use ExUnit.Case, async: true

  alias Instabot.Stories.AdClassifier

  describe "classify/1" do
    test "marks stories without Instagram chrome as likely ads" do
      assert %{likely_ad: true, ad_score: 5, ad_reasons: ["missing_story_header"]} =
               AdClassifier.classify(%{story_chrome_detected: false})
    end

    test "does not mark normal story chrome as an ad by itself" do
      assert %{likely_ad: false, ad_score: 0, ad_reasons: []} =
               AdClassifier.classify(%{story_chrome_detected: true})
    end

    test "uses OCR commerce text as an ad signal" do
      assert %{likely_ad: true, ad_reasons: reasons} =
               AdClassifier.classify(%{
                 story_chrome_detected: false,
                 ocr_text: "Vintage slub t-shirts\nNew colors added"
               })

      assert ["missing_story_header", "commerce_text"] == reasons
    end

    test "marks explicit sponsored text as likely ad" do
      assert %{likely_ad: true, ad_score: 6, ad_reasons: ["sponsored_text"]} =
               AdClassifier.classify(%{ocr_text: "Sponsored"})
    end
  end
end
