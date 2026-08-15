defmodule Instabot.Shops.ProductDataTest do
  use ExUnit.Case, async: true

  alias Instabot.Shops.ProductData

  defp public_resolver(_host), do: {:ok, [{93, 184, 216, 34}]}

  test "builds Shopify product json URLs" do
    assert "https://example.com/products/hat.js" ==
             ProductData.product_json_url("https://example.com/products/hat?variant=123")

    assert "https://example.com/products/hat.js" ==
             ProductData.product_json_url("https://example.com/products/hat.js")
  end

  test "parses Shopify product JavaScript JSON responses" do
    request = fn request ->
      [
        status: 200,
        body:
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
      ]
      |> Req.Response.new()
      |> then(&{request, &1})
    end

    assert {:ok,
            %{
              product_title: "Canvas Hat",
              product_price_cents: 2495,
              product_compare_at_price_cents: 3295,
              product_available: true
            }} =
             ProductData.fetch("https://shop.example/products/hat",
               resolver: &public_resolver/1,
               request_options: [adapter: request]
             )
  end

  test "rejects an unsafe redirect before requesting it" do
    request = fn request ->
      [status: 302, headers: %{"location" => ["http://169.254.169.254/latest"]}]
      |> Req.Response.new()
      |> then(&{request, &1})
    end

    assert {:error, :unsafe_url} ==
             ProductData.fetch("https://shop.example/products/hat",
               resolver: fn
                 "shop.example" -> {:ok, [{93, 184, 216, 34}]}
                 "169.254.169.254" -> {:ok, [{169, 254, 169, 254}]}
               end,
               request_options: [adapter: request]
             )
  end
end
