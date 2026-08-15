defmodule Instabot.Network.SafeUrlTest do
  use ExUnit.Case, async: true

  alias Instabot.Network.SafeUrl

  test "accepts public addresses on web ports" do
    resolver = fn "shop.example" -> {:ok, [{93, 184, 216, 34}, {0x2606, 0x2800, 0x220, 1, 0, 0, 0, 1}]} end

    assert {:ok, %URI{host: "shop.example"}} = SafeUrl.validate("https://shop.example/products", resolver)
    assert {:ok, %URI{port: 80}} = SafeUrl.validate("http://shop.example:80", resolver)
  end

  test "rejects unsafe URL structure" do
    resolver = fn _host -> {:ok, [{93, 184, 216, 34}]} end

    for url <- [
          "ftp://shop.example",
          "https://user:password@shop.example",
          "https://shop.example:444",
          "http://shop.example:8080",
          "not a url"
        ] do
      assert {:error, :unsafe_url} == SafeUrl.validate(url, resolver)
    end
  end

  test "rejects private and special-use IPv4 destinations" do
    for address <- [
          {0, 0, 0, 0},
          {10, 0, 0, 1},
          {100, 64, 0, 1},
          {127, 0, 0, 1},
          {169, 254, 169, 254},
          {172, 16, 0, 1},
          {192, 168, 0, 1},
          {198, 18, 0, 1},
          {224, 0, 0, 1}
        ] do
      resolver = fn _host -> {:ok, [address]} end
      assert {:error, :unsafe_url} == SafeUrl.validate("https://shop.example", resolver)
    end
  end

  test "rejects private, mapped, and special-use IPv6 destinations" do
    for address <- [
          {0, 0, 0, 0, 0, 0, 0, 0},
          {0, 0, 0, 0, 0, 0, 0, 1},
          {0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 1},
          {0x2001, 0x0DB8, 0, 0, 0, 0, 0, 1},
          {0xFC00, 0, 0, 0, 0, 0, 0, 1},
          {0xFE80, 0, 0, 0, 0, 0, 0, 1},
          {0xFF00, 0, 0, 0, 0, 0, 0, 1}
        ] do
      resolver = fn _host -> {:ok, [address]} end
      assert {:error, :unsafe_url} == SafeUrl.validate("https://shop.example", resolver)
    end
  end

  test "rejects mixed public and private DNS answers and resolution failures" do
    mixed_resolver = fn _host -> {:ok, [{93, 184, 216, 34}, {10, 0, 0, 1}]} end
    failed_resolver = fn _host -> {:error, :nxdomain} end

    assert {:error, :unsafe_url} == SafeUrl.validate("https://shop.example", mixed_resolver)
    assert {:error, :unsafe_url} == SafeUrl.validate("https://shop.example", failed_resolver)
  end
end
