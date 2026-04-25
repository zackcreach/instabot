defmodule Instabot.Scraping.Events do
  @moduledoc false

  @active_statuses [:queued, :started, :scraping_posts, :scraping_stories, :downstream]
  @terminal_statuses [:completed, :failed, :cancelled]

  def subscribe(user_id) do
    Phoenix.PubSub.subscribe(Instabot.PubSub, topic(user_id))
  end

  def build(profile, status, attrs \\ %{}) when is_atom(status) and is_map(attrs) do
    event(profile, status, attrs)
  end

  def broadcast(profile, status, attrs \\ %{}) when is_atom(status) and is_map(attrs) do
    event = event(profile, status, attrs)

    Phoenix.PubSub.broadcast(
      Instabot.PubSub,
      topic(profile.user_id),
      {:scrape_event, event}
    )

    :telemetry.execute([:instabot, :scrape, status], %{count: 1}, event)

    event
  end

  def active?(status), do: status in @active_statuses
  def terminal?(status), do: status in @terminal_statuses

  def topic(user_id), do: "scrape_updates:#{user_id}"

  defp event(profile, status, attrs) do
    %{
      profile_id: profile.id,
      user_id: profile.user_id,
      username: profile.instagram_username,
      status: status,
      step: Map.get(attrs, :step, status),
      message: Map.get(attrs, :message, default_message(status)),
      posts_found: Map.get(attrs, :posts_found),
      stories_found: Map.get(attrs, :stories_found),
      error: Map.get(attrs, :error),
      at: DateTime.utc_now(:second)
    }
  end

  defp default_message(:queued), do: "Queued"
  defp default_message(:started), do: "Starting"
  defp default_message(:scraping_posts), do: "Scraping posts"
  defp default_message(:scraping_stories), do: "Scraping stories"
  defp default_message(:downstream), do: "Processing media"
  defp default_message(:completed), do: "Scrape complete"
  defp default_message(:failed), do: "Scrape failed"
  defp default_message(:cancelled), do: "Scrape cancelled"
  defp default_message(_status), do: "Scrape updated"
end
