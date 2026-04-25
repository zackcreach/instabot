defmodule Instabot.Repo.Migrations.AddUniqueIndexToStories do
  use Ecto.Migration

  def up do
    execute """
    DELETE FROM stories
    WHERE id IN (
      SELECT id
      FROM (
        SELECT
          id,
          row_number() OVER (
            PARTITION BY tracked_profile_id, instagram_story_id
            ORDER BY inserted_at ASC, id ASC
          ) AS duplicate_rank
        FROM stories
      ) ranked_stories
      WHERE duplicate_rank > 1
    )
    """

    create unique_index(:stories, [:tracked_profile_id, :instagram_story_id])
  end

  def down do
    drop unique_index(:stories, [:tracked_profile_id, :instagram_story_id])
  end
end
