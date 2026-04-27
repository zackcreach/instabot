defmodule Instabot.Media.Cloudinary do
  @moduledoc """
  Cloudinary Upload API client for image assets.
  """

  @behaviour Instabot.Media.Storage

  @default_endpoint "https://api.cloudinary.com/v1_1"

  @impl true
  def upload_image(bytes, opts) when is_binary(bytes) do
    with {:ok, config} <- config(),
         {:ok, public_id} <- public_id(opts) do
      fields = [
        file: {bytes, filename: Keyword.fetch!(opts, :filename), content_type: Keyword.get(opts, :content_type)},
        public_id: public_id,
        overwrite: "true",
        resource_type: "image"
      ]

      fields =
        case config.folder do
          nil -> fields
          "" -> fields
          folder -> Keyword.put(fields, :folder, folder)
        end

      "#{config.endpoint}/#{config.cloud_name}/image/upload"
      |> Req.post(
        auth: {:basic, "#{config.api_key}:#{config.api_secret}"},
        form_multipart: fields,
        decode_body: :json,
        max_retries: 2
      )
      |> normalize_response()
    end
  end

  @impl true
  def download_to_temp(url, opts) when is_binary(url) do
    filename = Keyword.get_lazy(opts, :filename, fn -> temp_filename(url) end)
    path = Path.join(System.tmp_dir!(), filename)

    case Req.get(url, decode_body: false, max_retries: 2) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case File.write(path, body) do
          :ok -> {:ok, path}
          {:error, reason} -> {:error, {:write_failed, reason}}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp config do
    config = Application.get_env(:instabot, __MODULE__, [])

    with {:ok, cloud_name} <- fetch_config(config, :cloud_name),
         {:ok, api_key} <- fetch_config(config, :api_key),
         {:ok, api_secret} <- fetch_config(config, :api_secret) do
      {:ok,
       %{
         cloud_name: cloud_name,
         api_key: api_key,
         api_secret: api_secret,
         folder: Keyword.get(config, :folder),
         endpoint: Keyword.get(config, :endpoint, @default_endpoint)
       }}
    end
  end

  defp fetch_config(config, key) do
    case Keyword.get(config, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_config, key}}
    end
  end

  defp public_id(opts) do
    case Keyword.get(opts, :public_id) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_option, :public_id}}
    end
  end

  defp normalize_response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299 do
    body = decode_body(body)

    {:ok,
     %{
       cloudinary_public_id: body["public_id"],
       cloudinary_secure_url: body["secure_url"],
       cloudinary_version: version_to_string(body["version"]),
       cloudinary_format: body["format"],
       cloudinary_resource_type: body["resource_type"],
       file_size: body["bytes"],
       width: body["width"],
       height: body["height"]
     }}
  end

  defp normalize_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:http_error, status, decode_body(body)}}

  defp normalize_response({:error, reason}), do: {:error, reason}

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> body
    end
  end

  defp decode_body(body), do: body

  defp version_to_string(nil), do: nil
  defp version_to_string(version), do: to_string(version)

  defp temp_filename(url) do
    extension =
      url
      |> URI.parse()
      |> Map.get(:path, "")
      |> Path.extname()
      |> case do
        "" -> ".jpg"
        value -> value
      end

    "instabot_cloudinary_#{System.unique_integer([:positive])}#{extension}"
  end
end
