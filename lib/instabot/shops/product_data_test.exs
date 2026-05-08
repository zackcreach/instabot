defmodule Instabot.Shops.ProductDataTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias Instabot.Shops.ProductData

  test "builds Shopify product json URLs" do
    assert "https://example.com/products/hat.js" ==
             ProductData.product_json_url("https://example.com/products/hat?variant=123")

    assert "https://example.com/products/hat.js" ==
             ProductData.product_json_url("https://example.com/products/hat.js")
  end

  test "parses Shopify product JavaScript JSON responses" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "GET", "/products/hat.js", fn conn ->
      conn
      |> put_resp_content_type("application/javascript")
      |> resp(
        200,
        Jason.encode!(%{
          title: "Canvas Hat",
          variants: [
            %{
              available: true,
              price: 2495,
              compare_at_price: 3295
            }
          ]
        })
      )
    end)

    assert {:ok,
            %{
              product_title: "Canvas Hat",
              product_price_cents: 2495,
              product_compare_at_price_cents: 3295,
              product_available: true
            }} = ProductData.fetch("http://localhost:#{bypass.port}/products/hat")
  end
end
