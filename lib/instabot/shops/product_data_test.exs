defmodule Instabot.Shops.ProductDataTest do
  use ExUnit.Case, async: true

  alias Instabot.Shops.ProductData

  test "builds Shopify product json URLs" do
    assert "https://example.com/products/hat.js" ==
             ProductData.product_json_url("https://example.com/products/hat?variant=123")

    assert "https://example.com/products/hat.js" ==
             ProductData.product_json_url("https://example.com/products/hat.js")
  end
end
