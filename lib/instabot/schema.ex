defmodule Instabot.Schema do
  @moduledoc false

  defmacro __using__(opts) do
    quote do
      use Ecto.Schema

      prefix = unquote(opts[:prefix])

      @primary_key {:id, UXID, autogenerate: true, prefix: prefix, size: :medium}
      @foreign_key_type UXID
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
