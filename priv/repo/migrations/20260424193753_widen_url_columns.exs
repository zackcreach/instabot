defmodule Instabot.Repo.Migrations.WidenUrlColumns do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      modify :media_urls, {:array, :text}, default: [], from: {:array, :string}
    end

    alter table(:stories) do
      modify :media_url, :text, from: :string
      modify :screenshot_path, :text, from: :string
    end
  end
end
