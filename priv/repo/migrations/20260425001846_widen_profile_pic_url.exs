defmodule Instabot.Repo.Migrations.WidenProfilePicUrl do
  use Ecto.Migration

  def change do
    alter table(:tracked_profiles) do
      modify :profile_pic_url, :text
    end
  end
end
