defmodule Instabot.Repo.Migrations.AddPostImagePositionIntegrity do
  use Ecto.Migration

  import Ecto.Query

  def up do
    alter table(:post_images) do
      add :exact_sha256, :text
    end

    flush()
    resequence_post_images()
    deduplicate_media_fingerprints()

    create unique_index(:post_images, [:post_id, :position])
    create unique_index(:media_fingerprints, [:source_kind, :source_id, :media_position])
  end

  def down do
    drop unique_index(:media_fingerprints, [:source_kind, :source_id, :media_position])
    drop unique_index(:post_images, [:post_id, :position])

    alter table(:post_images) do
      remove :exact_sha256
    end
  end

  defp resequence_post_images do
    from(image in "post_images",
      order_by: [asc: image.post_id, asc: image.position, asc: image.inserted_at, asc: image.id],
      select: %{id: image.id, post_id: image.post_id}
    )
    |> repo().all()
    |> Enum.group_by(& &1.post_id)
    |> Enum.each(fn {_post_id, images} ->
      images
      |> Enum.with_index()
      |> Enum.each(fn {image, position} ->
        repo().update_all(
          from(stored_image in "post_images", where: stored_image.id == ^image.id),
          set: [position: position]
        )
      end)
    end)
  end

  defp deduplicate_media_fingerprints do
    duplicate_ids =
      from(fingerprint in "media_fingerprints",
        order_by: [
          asc: fingerprint.source_kind,
          asc: fingerprint.source_id,
          asc: fingerprint.media_position,
          asc: fingerprint.inserted_at,
          asc: fingerprint.id
        ],
        select: %{
          id: fingerprint.id,
          source_kind: fingerprint.source_kind,
          source_id: fingerprint.source_id,
          media_position: fingerprint.media_position
        }
      )
      |> repo().all()
      |> Enum.group_by(&{&1.source_kind, &1.source_id, &1.media_position})
      |> Enum.flat_map(fn {_source, [_fingerprint | duplicates]} ->
        Enum.map(duplicates, & &1.id)
      end)

    repo().delete_all(
      from(fingerprint in "media_fingerprints", where: fingerprint.id in ^duplicate_ids)
    )
  end
end
