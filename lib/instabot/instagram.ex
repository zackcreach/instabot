defmodule Instabot.Instagram do
  @moduledoc """
  The Instagram context for managing connections, tracked profiles, posts, stories, and scrape logs.
  """

  import Ecto.Query

  alias Instabot.Instagram.InstagramConnection
  alias Instabot.Instagram.Post
  alias Instabot.Instagram.PostImage
  alias Instabot.Instagram.ScrapeLog
  alias Instabot.Instagram.Story
  alias Instabot.Instagram.TrackedProfile
  alias Instabot.Repo

  def get_connection_for_user(user_id) do
    Repo.get_by(InstagramConnection, user_id: user_id)
  end

  def create_connection(user_id, attrs) do
    %InstagramConnection{user_id: user_id}
    |> InstagramConnection.changeset(attrs)
    |> Repo.insert()
  end

  def upsert_connection(user_id, attrs) do
    %InstagramConnection{user_id: user_id}
    |> InstagramConnection.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:instagram_username, :encrypted_password, :status, :updated_at]},
      conflict_target: :user_id,
      returning: true
    )
  end

  def update_connection(%InstagramConnection{} = connection, attrs) do
    connection
    |> InstagramConnection.changeset(attrs)
    |> Repo.update()
  end

  def store_cookies(%InstagramConnection{} = connection, encrypted_cookies, expires_at) do
    connection
    |> InstagramConnection.changeset(%{
      encrypted_cookies: encrypted_cookies,
      status: "connected",
      cookies_expire_at: expires_at,
      last_login_at: DateTime.utc_now(:second)
    })
    |> Repo.update()
  end

  def mark_connection_expired(%InstagramConnection{} = connection) do
    connection
    |> InstagramConnection.changeset(%{status: "expired"})
    |> Repo.update()
  end

  def list_tracked_profiles(user_id) do
    TrackedProfile
    |> where(user_id: ^user_id)
    |> order_by(asc: :instagram_username)
    |> Repo.all()
  end

  def get_tracked_profile!(id), do: Repo.get!(TrackedProfile, id)

  def get_tracked_profile_for_user!(user_id, id) do
    TrackedProfile
    |> where(user_id: ^user_id, id: ^id)
    |> Repo.one!()
  end

  def count_tracked_profiles(user_id) do
    TrackedProfile
    |> where(user_id: ^user_id)
    |> Repo.aggregate(:count)
  end

  def create_tracked_profile(user_id, attrs) do
    %TrackedProfile{user_id: user_id}
    |> TrackedProfile.changeset(attrs)
    |> Repo.insert()
  end

  def change_tracked_profile(%TrackedProfile{} = profile, attrs \\ %{}) do
    TrackedProfile.changeset(profile, attrs)
  end

  def delete_tracked_profile(%TrackedProfile{} = profile) do
    Repo.delete(profile)
  end

  def toggle_active(%TrackedProfile{} = profile) do
    profile
    |> Ecto.Changeset.change(%{is_active: not profile.is_active})
    |> Repo.update()
  end

  def update_tracked_profile_metadata(%TrackedProfile{} = profile, attrs) do
    profile
    |> TrackedProfile.changeset(attrs)
    |> Repo.update()
  end

  def update_last_scraped(%TrackedProfile{} = profile) do
    profile
    |> Ecto.Changeset.change(%{last_scraped_at: DateTime.utc_now(:second)})
    |> Repo.update()
  end

  def list_active_tracked_profiles do
    TrackedProfile
    |> where(is_active: true)
    |> preload(:user)
    |> Repo.all()
  end

  def create_post(tracked_profile_id, attrs) do
    %Post{tracked_profile_id: tracked_profile_id}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  def upsert_post_from_scrape(tracked_profile_id, attrs) do
    case get_post_by_instagram_id(tracked_profile_id, attrs[:instagram_post_id] || attrs["instagram_post_id"]) do
      nil ->
        tracked_profile_id
        |> create_post(attrs)
        |> tag_post_result(:inserted)

      %Post{} = post ->
        post
        |> Post.changeset(scrape_update_attrs(post, attrs))
        |> update_scraped_post()
    end
  end

  def count_posts(user_id) do
    Post
    |> join(:inner, [p], tp in TrackedProfile, on: p.tracked_profile_id == tp.id)
    |> where([_p, tp], tp.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  def create_post_image(post_id, attrs) do
    %PostImage{post_id: post_id}
    |> PostImage.changeset(attrs)
    |> Repo.insert()
  end

  def get_posts_needing_images(tracked_profile_id) do
    Post
    |> where(tracked_profile_id: ^tracked_profile_id)
    |> where([p], p.media_urls != ^[])
    |> preload(:post_images)
    |> Repo.all()
    |> Enum.filter(fn post ->
      length(post.post_images) < length(post.media_urls)
    end)
  end

  def create_story(tracked_profile_id, attrs) do
    %Story{tracked_profile_id: tracked_profile_id}
    |> Story.changeset(attrs)
    |> Repo.insert()
  end

  def upsert_story_from_scrape(tracked_profile_id, attrs) do
    case get_story_by_instagram_id(tracked_profile_id, attrs[:instagram_story_id] || attrs["instagram_story_id"]) do
      nil ->
        tracked_profile_id
        |> create_story(attrs)
        |> tag_story_result(:inserted)

      %Story{} = story ->
        story
        |> Story.changeset(scrape_update_attrs(story, attrs))
        |> update_scraped_story()
    end
  end

  def count_stories(user_id) do
    Story
    |> join(:inner, [s], tp in TrackedProfile, on: s.tracked_profile_id == tp.id)
    |> where([_s, tp], tp.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  def get_story!(id), do: Repo.get!(Story, id)

  def update_story_ocr(%Story{} = story, attrs) do
    story
    |> Story.changeset(attrs)
    |> Repo.update()
  end

  def get_stories_pending_ocr(tracked_profile_id) do
    Story
    |> where(tracked_profile_id: ^tracked_profile_id)
    |> where([s], s.ocr_status in ["pending", "failed"] and not is_nil(s.screenshot_path))
    |> Repo.all()
  end

  def count_stories_waiting_for_ocr(tracked_profile_id) do
    Story
    |> where(tracked_profile_id: ^tracked_profile_id)
    |> where([s], s.ocr_status in ["pending", "processing"] and not is_nil(s.screenshot_path))
    |> Repo.aggregate(:count)
  end

  def get_new_posts_since(user_id, since) do
    Post
    |> join(:inner, [p], tp in TrackedProfile, on: p.tracked_profile_id == tp.id)
    |> where([_p, tp], tp.user_id == ^user_id)
    |> where([p, _tp], p.inserted_at >= ^since)
    |> preload([:post_images, :tracked_profile])
    |> Repo.all()
  end

  def get_new_stories_since(user_id, since) do
    Story
    |> join(:inner, [s], tp in TrackedProfile, on: s.tracked_profile_id == tp.id)
    |> where([_s, tp], tp.user_id == ^user_id)
    |> where([s, _tp], s.inserted_at >= ^since)
    |> preload(:tracked_profile)
    |> Repo.all()
  end

  def create_scrape_log(tracked_profile_id, attrs) do
    %ScrapeLog{tracked_profile_id: tracked_profile_id}
    |> ScrapeLog.changeset(Map.put(attrs, :started_at, DateTime.utc_now(:second)))
    |> Repo.insert()
  end

  def complete_scrape_log(%ScrapeLog{} = log, attrs) do
    log
    |> ScrapeLog.changeset(Map.merge(attrs, %{status: "completed", completed_at: DateTime.utc_now(:second)}))
    |> Repo.update()
  end

  def fail_scrape_log(%ScrapeLog{} = log, error_message) do
    log
    |> ScrapeLog.changeset(%{
      status: "failed",
      error_message: error_message,
      completed_at: DateTime.utc_now(:second)
    })
    |> Repo.update()
  end

  defp get_post_by_instagram_id(_tracked_profile_id, instagram_post_id) when instagram_post_id in [nil, ""], do: nil

  defp get_post_by_instagram_id(tracked_profile_id, instagram_post_id) do
    Repo.get_by(Post, tracked_profile_id: tracked_profile_id, instagram_post_id: instagram_post_id)
  end

  defp get_story_by_instagram_id(_tracked_profile_id, instagram_story_id) when instagram_story_id in [nil, ""], do: nil

  defp get_story_by_instagram_id(tracked_profile_id, instagram_story_id) do
    Repo.get_by(Story, tracked_profile_id: tracked_profile_id, instagram_story_id: instagram_story_id)
  end

  defp scrape_update_attrs(record, attrs) do
    attrs
    |> normalize_attrs()
    |> Enum.reject(fn {key, value} ->
      blank_scrape_value?(key, value) and not blank_existing_value?(Map.get(record, key))
    end)
    |> reset_story_ocr_attrs(record)
    |> Map.new()
  end

  defp reset_story_ocr_attrs(attrs, %Story{} = story) do
    case Keyword.get(attrs, :screenshot_path) do
      screenshot_path when is_binary(screenshot_path) and screenshot_path != story.screenshot_path ->
        attrs
        |> Keyword.put(:ocr_status, "pending")
        |> Keyword.put(:ocr_text, nil)

      _ ->
        attrs
    end
  end

  defp reset_story_ocr_attrs(attrs, _record), do: attrs

  defp normalize_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn {key, value}, acc ->
      Map.put(acc, normalize_key(key), value)
    end)
  end

  defp normalize_key(key) when is_binary(key), do: String.to_existing_atom(key)
  defp normalize_key(key), do: key

  defp blank_scrape_value?(key, value) when key in [:caption, :permalink], do: is_nil(value) or String.trim(value) == ""

  defp blank_scrape_value?(key, value) when key in [:hashtags, :media_urls], do: value in [nil, []]
  defp blank_scrape_value?(_key, value), do: is_nil(value)

  defp blank_existing_value?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_existing_value?(value), do: value in [nil, []]

  defp update_scraped_post(%Ecto.Changeset{changes: changes, data: post}) when changes == %{}, do: {:ok, post, :unchanged}

  defp update_scraped_post(changeset) do
    changeset
    |> Repo.update()
    |> tag_post_result(:updated)
  end

  defp update_scraped_story(%Ecto.Changeset{changes: changes, data: story}) when changes == %{},
    do: {:ok, story, :unchanged}

  defp update_scraped_story(changeset) do
    changeset
    |> Repo.update()
    |> tag_story_result(:updated)
  end

  defp tag_post_result({:ok, post}, status), do: {:ok, post, status}
  defp tag_post_result({:error, changeset}, _status), do: {:error, changeset}

  defp tag_story_result({:ok, story}, status), do: {:ok, story, status}
  defp tag_story_result({:error, changeset}, _status), do: {:error, changeset}
end
