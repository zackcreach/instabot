defmodule Instabot.Media.DownloaderTest do
  use ExUnit.Case, async: true

  alias Instabot.Media.Downloader

  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0>>
  @public_address [{93, 184, 216, 34}]

  test "accepts a bounded image from a public HTTPS URL" do
    assert {:ok, %Req.Response{body: @jpeg}} =
             fetch(response(status: 200, headers: image_headers(), body: @jpeg))
  end

  test "rejects private destinations before requesting them" do
    assert {:error, :unsafe_url} ==
             Downloader.fetch("https://media.example/image.jpg",
               resolver: fn _host -> {:ok, [{169, 254, 169, 254}]} end,
               request_options: [adapter: fn _request -> flunk("unsafe destination was requested") end]
             )
  end

  test "rejects HTTP and nonstandard ports" do
    for url <- ["http://media.example/image.jpg", "https://media.example:8443/image.jpg"] do
      assert {:error, :unsafe_url} ==
               Downloader.fetch(url,
                 resolver: fn _host -> {:ok, @public_address} end,
                 request_options: [adapter: fn _request -> flunk("unsafe destination was requested") end]
               )
    end
  end

  test "validates every redirect destination" do
    redirect = response(status: 302, headers: %{"location" => ["https://169.254.169.254/image.jpg"]})

    assert {:error, :unsafe_url} ==
             Downloader.fetch("https://media.example/image.jpg",
               resolver: fn
                 "media.example" -> {:ok, @public_address}
                 "169.254.169.254" -> {:ok, [{169, 254, 169, 254}]}
               end,
               request_options: [adapter: fn request -> {request, redirect} end]
             )
  end

  test "rejects oversized responses with or without a content length" do
    oversized = @jpeg <> "too large"

    for headers <- [image_headers(), Map.put(image_headers(), "content-length", [to_string(byte_size(oversized))])] do
      assert {:error, :response_too_large} ==
               fetch(response(status: 200, headers: headers, body: oversized), maximum_bytes: byte_size(@jpeg))
    end
  end

  test "rejects missing, unsupported, and misleading content types" do
    assert {:error, :missing_content_type} == fetch(response(status: 200, body: @jpeg))

    assert {:error, :unsupported_content_type} ==
             fetch(response(status: 200, headers: %{"content-type" => ["text/html"]}, body: @jpeg))

    assert {:error, :invalid_image} ==
             fetch(response(status: 200, headers: image_headers(), body: "not an image"))
  end

  defp fetch(response, options \\ []) do
    request_options = [adapter: fn request -> {request, response} end]

    Downloader.fetch(
      "https://media.example/image.jpg",
      [resolver: fn _host -> {:ok, @public_address} end, request_options: request_options] ++ options
    )
  end

  defp response(options), do: Req.Response.new(options)
  defp image_headers, do: %{"content-type" => ["image/jpeg"]}
end
