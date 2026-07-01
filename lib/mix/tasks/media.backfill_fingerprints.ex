defmodule Mix.Tasks.Media.BackfillFingerprints do
  @shortdoc "Reports or backfills media fingerprints"

  @moduledoc """
  Reports visual duplicates and optionally records media fingerprints for existing media.

      mix media.backfill_fingerprints
      mix media.backfill_fingerprints --commit
  """

  use Mix.Task

  import Ecto.Query

  alias Instabot.Instagram
  alias Instabot.Instagram.Post
  alias Instabot.Instagram.PostImage
  alias Instabot.Instagram.Story
  alias Instabot.Media
  alias Instabot.Media.Fingerprint
  alias Instabot.Repo

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    commit? = "--commit" in args
    post_results = backfill_post_images(commit?)
    story_results = backfill_stories(commit?)

    IO.puts("Mode: #{mode(commit?)}")
    IO.puts("Post images: #{format_counts(post_results)}")
    IO.puts("Stories: #{format_counts(story_results)}")
  end

  defp backfill_post_images(commit?) do
    PostImage
    |> join(:inner, [post_image], post in Post, on: post_image.post_id == post.id)
    |> order_by([post_image, post], asc: post.tracked_profile_id, asc: post.inserted_at, asc: post_image.position)
    |> preload(:post)
    |> Repo.all()
    |> reduce_backfill(commit?, &post_image_fingerprint/1, &post_image_source/1)
  end

  defp post_image_fingerprint(%PostImage{} = post_image) do
    with {:ok, bytes} <- read_media(post_image.cloudinary_secure_url, post_image.local_path, post_image.original_url),
         {:ok, fingerprint} <- Fingerprint.from_bytes(bytes) do
      {:ok, Map.put(fingerprint, :media_position, post_image.position)}
    else
      {:error, :enoent} -> :missing
      {:error, _reason} -> :failed
    end
  end

  defp post_image_source(%PostImage{} = post_image), do: {post_image.post.tracked_profile_id, :post, post_image.post_id}

  defp backfill_stories(commit?) do
    Story
    |> order_by([story], asc: story.tracked_profile_id, asc: story.inserted_at)
    |> Repo.all()
    |> reduce_backfill(commit?, &story_fingerprint/1, &story_source/1)
  end

  defp story_fingerprint(%Story{} = story) do
    with {:ok, bytes} <- read_media(story.screenshot_url, story.screenshot_path, story.media_url),
         {:ok, fingerprint} <- Fingerprint.from_bytes(bytes) do
      {:ok, fingerprint}
    else
      {:error, :enoent} -> :missing
      {:error, _reason} -> :failed
    end
  end

  defp story_source(%Story{} = story), do: {story.tracked_profile_id, :story, story.id}

  defp reduce_backfill(records, commit?, fingerprint_fun, source_fun) do
    {counts, _seen} =
      Enum.reduce(records, {%{}, []}, fn record, {counts, seen} ->
        case fingerprint_fun.(record) do
          {:ok, fingerprint} ->
            {tracked_profile_id, source_kind, source_id} = source_fun.(record)

            {status, updated_seen} =
              register_or_report(tracked_profile_id, source_kind, source_id, fingerprint, seen, commit?)

            {increment_count(counts, status), updated_seen}

          status when status in [:missing, :failed] ->
            {increment_count(counts, status), seen}
        end
      end)

    counts
  end

  defp register_or_report(tracked_profile_id, source_kind, source_id, fingerprint, seen, commit?) do
    duplicate? =
      match?(
        %Instabot.Instagram.MediaFingerprint{},
        Instagram.find_duplicate_media_fingerprint(tracked_profile_id, fingerprint)
      ) or
        Enum.any?(seen, fn {seen_profile_id, seen_fingerprint} ->
          seen_profile_id == tracked_profile_id and Fingerprint.duplicate?(seen_fingerprint, fingerprint)
        end)

    if duplicate? do
      {:duplicate, seen}
    else
      status =
        if commit? do
          case Instagram.create_media_fingerprint(tracked_profile_id, source_kind, source_id, fingerprint) do
            {:ok, _media_fingerprint} -> :registered
            {:error, _changeset} -> :failed
          end
        else
          :would_register
        end

      {status, [{tracked_profile_id, fingerprint} | seen]}
    end
  end

  defp increment_count(counts, status), do: Map.update(counts, status, 1, &(&1 + 1))

  defp read_media(values) do
    values
    |> Enum.reject(&blank?/1)
    |> Enum.find_value(&read_media_value/1)
    |> case do
      {:ok, bytes} -> {:ok, bytes}
      nil -> {:error, :enoent}
    end
  end

  defp read_media(first, second, third), do: read_media([first, second, third])

  defp read_media_value(value) do
    if String.starts_with?(value, "http://") or String.starts_with?(value, "https://") do
      case Media.download(value) do
        {:ok, %{body: bytes}} -> {:ok, bytes}
        {:error, _reason} -> nil
      end
    else
      value
      |> local_path_candidates()
      |> Enum.find_value(fn candidate ->
        case File.read(candidate) do
          {:ok, bytes} -> {:ok, bytes}
          {:error, _reason} -> nil
        end
      end)
    end
  end

  defp local_path_candidates(path) do
    case Media.to_url(path) do
      "/" <> relative_path -> [path, Path.join("priv/static", relative_path)]
      _url -> [path]
    end
  end

  defp format_counts(counts) do
    Enum.map_join([:registered, :would_register, :duplicate, :missing, :failed], ", ", fn status ->
      "#{status}=#{Map.get(counts, status, 0)}"
    end)
  end

  defp mode(true), do: "commit"
  defp mode(false), do: "dry-run"

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true
end
