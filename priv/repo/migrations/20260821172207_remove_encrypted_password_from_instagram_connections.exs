defmodule Instabot.Repo.Migrations.RemoveEncryptedPasswordFromInstagramConnections do
  use Ecto.Migration

  def change do
    alter table(:instagram_connections) do
      remove :encrypted_password, :binary
    end
  end
end
