defmodule Instabot.Utils.Migrations do
  @moduledoc """
  Migration helpers for generating prefixed UXID primary keys at the database level.
  """

  defp gen_fragment(prefix) do
    "('#{prefix}_' || substr(replace(gen_random_uuid()::text, '-', ''), 0, 20))"
  end

  @doc """
  Adds a prefixed text primary key with a database-level default using `gen_random_uuid()`.
  """
  defmacro id(prefix) do
    quote do
      add(:id, :text,
        primary_key: true,
        default: fragment(unquote(gen_fragment(prefix)))
      )
    end
  end

  defmacro __using__(_opts) do
    quote do
      use Ecto.Migration

      import Instabot.Utils.Migrations
    end
  end
end
