defmodule Instabot.Media.Storage do
  @moduledoc """
  Storage adapter contract for media assets.
  """

  @callback upload_image(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback download_to_temp(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
end
