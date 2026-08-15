defmodule Instabot.Shops.ProductData do
  @moduledoc false

  alias Instabot.Network.SafeUrl

  @maximum_redirects 5

  def fetch(nil), do: {:ok, %{}}
  def fetch(""), do: {:ok, %{}}

  def fetch(product_url, options \\ []) do
    resolver = Keyword.get(options, :resolver, &SafeUrl.resolve/1)
    request_options = Keyword.get(options, :request_options, [])

    product_url
    |> product_json_url()
    |> request(resolver, request_options, @maximum_redirects)
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

  defp request(url, resolver, request_options, redirects_remaining) do
    with {:ok, _uri} <- SafeUrl.validate(url, resolver),
         {:ok, response} <- Req.get(url, [decode_body: false, redirect: false] ++ request_options) do
      follow_redirect(response, url, resolver, request_options, redirects_remaining)
    end
  end

  defp follow_redirect(%Req.Response{status: status} = response, _url, _resolver, _request_options, _remaining)
       when status not in 300..399, do: {:ok, response}

  defp follow_redirect(_response, _url, _resolver, _request_options, 0), do: {:error, :too_many_redirects}

  defp follow_redirect(response, url, resolver, request_options, redirects_remaining) do
    case Req.Response.get_header(response, "location") do
      [location | _rest] ->
        url
        |> URI.merge(location)
        |> URI.to_string()
        |> request(resolver, request_options, redirects_remaining - 1)

      [] ->
        {:error, :invalid_redirect}
    end
  end

  defp parse_response({:ok, %{status: 200, body: body}}) when is_map(body) do
    {:ok, parse_product(body)}
  end

  defp parse_response({:ok, %{status: 200, body: body}}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, product} when is_map(product) -> {:ok, parse_product(product)}
      {:ok, _decoded} -> {:error, :invalid_product_payload}
      {:error, reason} -> {:error, {:invalid_product_payload, reason}}
    end
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
