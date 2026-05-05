defmodule Instabot.Shops.ProductData do
  @moduledoc false

  def fetch(nil), do: {:ok, %{}}
  def fetch(""), do: {:ok, %{}}

  def fetch(product_url) do
    product_url
    |> product_json_url()
    |> Req.get()
    |> parse_response()
  end

  def product_json_url(product_url) do
    uri = URI.parse(product_url)
    path = uri.path || ""

    path =
      path
      |> String.trim_trailing("/")
      |> ensure_json_extension()

    URI.to_string(%{uri | path: path, query: nil, fragment: nil})
  end

  defp ensure_json_extension(path) do
    if String.ends_with?(path, ".js"), do: path, else: path <> ".js"
  end

  defp parse_response({:ok, %{status: 200, body: body}}) when is_map(body) do
    {:ok, parse_product(body)}
  end

  defp parse_response({:ok, %{status: status}}), do: {:error, {:product_request_failed, status}}
  defp parse_response({:error, reason}), do: {:error, reason}

  defp parse_product(product) do
    variants = Map.get(product, "variants", [])
    selected_variant = Enum.find(variants, &Map.get(&1, "available")) || List.first(variants) || %{}

    %{
      product_title: Map.get(product, "title"),
      product_price_cents: integer_value(Map.get(selected_variant, "price")),
      product_compare_at_price_cents: integer_value(Map.get(selected_variant, "compare_at_price")),
      product_currency: Map.get(product, "currency") || Map.get(selected_variant, "currency"),
      product_available: Map.get(selected_variant, "available")
    }
  end

  defp integer_value(nil), do: nil
  defp integer_value(value) when is_integer(value), do: value
  defp integer_value(value) when is_float(value), do: round(value)

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, _rest} -> integer
      :error -> nil
    end
  end
end
