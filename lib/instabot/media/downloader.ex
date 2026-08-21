defmodule Instabot.Media.Downloader do
  @moduledoc false

  alias Instabot.Network.SafeUrl

  @allowed_content_types ["image/avif", "image/gif", "image/jpeg", "image/png", "image/webp"]
  @default_maximum_bytes 15 * 1024 * 1024
  @maximum_redirects 5

  def fetch(url, options \\ []) do
    resolver = Keyword.get(options, :resolver, &SafeUrl.resolve/1)
    request_options = Keyword.get(options, :request_options, [])
    maximum_bytes = Keyword.get(options, :maximum_bytes, @default_maximum_bytes)

    request(url, resolver, request_options, maximum_bytes, @maximum_redirects)
  end

  defp request(url, resolver, request_options, maximum_bytes, redirects_remaining) do
    with {:ok, _uri} <- validate_url(url, resolver),
         {:ok, response} <- stream(url, request_options, maximum_bytes) do
      handle_response(response, url, resolver, request_options, maximum_bytes, redirects_remaining)
    end
  end

  defp validate_url(url, resolver) do
    with {:ok, %URI{scheme: "https", port: port} = uri} <- SafeUrl.validate(url, resolver),
         true <- is_nil(port) or port == 443 do
      {:ok, uri}
    else
      _reason -> {:error, :unsafe_url}
    end
  end

  defp stream(url, request_options, maximum_bytes) do
    options =
      [
        decode_body: false,
        redirect: false,
        max_retries: 2,
        into: stream_body(maximum_bytes)
      ] ++ request_options

    Req.get(url, options)
  end

  defp stream_body(maximum_bytes) do
    fn {:data, data}, accumulator -> append_body(data, accumulator, maximum_bytes) end
  end

  defp append_body(data, {request, response}, maximum_bytes)
       when byte_size(response.body) + byte_size(data) <= maximum_bytes,
       do: {:cont, {request, %{response | body: response.body <> data}}}

  defp append_body(_data, {request, response}, _maximum_bytes),
    do: {:halt, {request, %{response | body: {:error, :response_too_large}}}}

  defp handle_response(%Req.Response{status: status} = response, url, resolver, request_options, maximum_bytes, remaining)
       when status in 300..399 do
    follow_redirect(response, url, resolver, request_options, maximum_bytes, remaining)
  end

  defp handle_response(
         %Req.Response{status: 200, body: {:error, reason}},
         _url,
         _resolver,
         _options,
         _maximum_bytes,
         _remaining
       ), do: {:error, reason}

  defp handle_response(%Req.Response{status: 200} = response, _url, _resolver, _options, maximum_bytes, _remaining) do
    with :ok <- validate_content_length(response, maximum_bytes),
         :ok <- validate_body_size(response.body, maximum_bytes),
         {:ok, content_type} <- content_type(response),
         :ok <- validate_signature(content_type, response.body) do
      {:ok, %{response | body: response.body, private: Map.put(response.private, :media_content_type, content_type)}}
    end
  end

  defp handle_response(%Req.Response{status: status}, _url, _resolver, _options, _maximum_bytes, _remaining),
    do: {:error, {:http_error, status}}

  defp validate_body_size(body, maximum_bytes) when byte_size(body) <= maximum_bytes, do: :ok
  defp validate_body_size(_body, _maximum_bytes), do: {:error, :response_too_large}

  defp follow_redirect(_response, _url, _resolver, _options, _maximum_bytes, 0), do: {:error, :too_many_redirects}

  defp follow_redirect(response, url, resolver, request_options, maximum_bytes, redirects_remaining) do
    case Req.Response.get_header(response, "location") do
      [location | _rest] ->
        url
        |> URI.merge(location)
        |> URI.to_string()
        |> request(resolver, request_options, maximum_bytes, redirects_remaining - 1)

      [] ->
        {:error, :invalid_redirect}
    end
  end

  defp validate_content_length(response, maximum_bytes) do
    case Req.Response.get_header(response, "content-length") do
      [] -> :ok
      [value | _rest] -> validate_content_length_value(value, maximum_bytes)
    end
  end

  defp validate_content_length_value(value, maximum_bytes) do
    case Integer.parse(value) do
      {size, ""} when size <= maximum_bytes -> :ok
      {size, ""} when size > maximum_bytes -> {:error, :response_too_large}
      _result -> {:error, :invalid_content_length}
    end
  end

  defp content_type(response) do
    case Req.Response.get_header(response, "content-type") do
      [value | _rest] ->
        value
        |> String.split(";", parts: 2)
        |> List.first()
        |> String.trim()
        |> String.downcase()
        |> allowed_content_type()

      [] ->
        {:error, :missing_content_type}
    end
  end

  defp allowed_content_type(content_type) when content_type in @allowed_content_types, do: {:ok, content_type}
  defp allowed_content_type(_content_type), do: {:error, :unsupported_content_type}

  defp validate_signature("image/jpeg", <<0xFF, 0xD8, 0xFF, _rest::binary>>), do: :ok
  defp validate_signature("image/png", <<0x89, "PNG\r\n", 0x1A, "\n", _rest::binary>>), do: :ok
  defp validate_signature("image/gif", <<"GIF87a", _rest::binary>>), do: :ok
  defp validate_signature("image/gif", <<"GIF89a", _rest::binary>>), do: :ok
  defp validate_signature("image/webp", <<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: :ok
  defp validate_signature("image/avif", <<_size::binary-size(4), "ftypavif", _rest::binary>>), do: :ok
  defp validate_signature(_content_type, _body), do: {:error, :invalid_image}
end
