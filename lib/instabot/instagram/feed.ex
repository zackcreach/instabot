defmodule Instabot.Instagram.Feed do
  @moduledoc """
  Pure query layer for the content feed views.

  All queries join through `TrackedProfile.user_id` so content from other users'
  tracked profiles can never leak through. Functions that accept opts support:

    * `:profile_id` — scope to one tracked profile (string or `nil`/`""` for all)
    * `:search` — ILIKE match against post caption and hashtag array
    * `:limit` — page size (default 24)
    * `:offset` — zero-based offset for pagination
  """

  import Ecto.Query

  alias Instabot.Instagram.Post
  alias Instabot.Instagram.Story
  alias Instabot.Instagram.TrackedProfile
  alias Instabot.Repo

  @default_limit 24

  def default_limit, do: @default_limit

  def list_posts(user_id, opts \\ []) do
    user_id
    |> posts_query(opts)
    |> order_by([p, _tp], desc: p.posted_at, desc: p.inserted_at)
    |> limit(^Keyword.get(opts, :limit, @default_limit))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> preload([:post_images, :tracked_profile])
    |> Repo.all()
  end

  def count_posts(user_id, opts \\ []) do
    user_id
    |> posts_query(opts)
    |> Repo.aggregate(:count)
  end

  def get_post_for_user!(user_id, post_id) do
    Post
    |> join(:inner, [p], tp in TrackedProfile, on: p.tracked_profile_id == tp.id)
    |> where([_p, tp], tp.user_id == ^user_id)
    |> where([p, _tp], p.id == ^post_id)
    |> preload([:post_images, :tracked_profile])
    |> Repo.one!()
  end

  def list_stories(user_id, opts \\ []) do
    user_id
    |> stories_query(opts)
    |> order_by([s, _tp], desc: s.posted_at, desc: s.inserted_at)
    |> limit(^Keyword.get(opts, :limit, @default_limit))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> preload(:tracked_profile)
    |> Repo.all()
  end

  def count_stories(user_id, opts \\ []) do
    user_id
    |> stories_query(opts)
    |> Repo.aggregate(:count)
  end

  def get_story_for_user!(user_id, story_id) do
    Story
    |> join(:inner, [s], tp in TrackedProfile, on: s.tracked_profile_id == tp.id)
    |> where([_s, tp], tp.user_id == ^user_id)
    |> where([s, _tp], s.id == ^story_id)
    |> preload(:tracked_profile)
    |> Repo.one!()
  end

  defp posts_query(user_id, opts) do
    Post
    |> join(:inner, [p], tp in TrackedProfile, on: p.tracked_profile_id == tp.id)
    |> where([_p, tp], tp.user_id == ^user_id)
    |> filter_posts_by_profile(opts[:profile_id])
    |> filter_posts_by_search(opts[:search])
  end

  defp filter_posts_by_profile(query, profile_id) when profile_id in [nil, ""], do: query

  defp filter_posts_by_profile(query, profile_id) do
    where(query, [p, _tp], p.tracked_profile_id == ^profile_id)
  end

  defp filter_posts_by_search(query, search) when search in [nil, ""], do: query

  defp filter_posts_by_search(query, search) do
    pattern = "%" <> escape_like(search) <> "%"

    where(
      query,
      [p, _tp],
      ilike(p.caption, ^pattern) or
        fragment(
          "EXISTS(SELECT 1 FROM unnest(?) AS h WHERE h ILIKE ? ESCAPE '\\')",
          p.hashtags,
          ^pattern
        )
    )
  end

  defp escape_like(search) do
    search
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp stories_query(user_id, opts) do
    Story
    |> join(:inner, [s], tp in TrackedProfile, on: s.tracked_profile_id == tp.id)
    |> where([_s, tp], tp.user_id == ^user_id)
    |> filter_stories_by_profile(opts[:profile_id])
  end

  defp filter_stories_by_profile(query, profile_id) when profile_id in [nil, ""], do: query

  defp filter_stories_by_profile(query, profile_id) do
    where(query, [s, _tp], s.tracked_profile_id == ^profile_id)
  end
end
