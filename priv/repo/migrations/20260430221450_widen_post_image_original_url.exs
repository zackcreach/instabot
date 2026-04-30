defmodule Instabot.Repo.Migrations.WidenPostImageOriginalUrl do
  use Ecto.Migration

  def change do
    alter table(:post_images) do
      modify :original_url, :text, null: false, from: {:string, null: false}
    end
  end
end
