defmodule Instabot.Instagram.Events do
  @moduledoc false

  def subscribe(user_id) do
    Phoenix.PubSub.subscribe(Instabot.PubSub, topic(user_id))
  end

  def broadcast_post_created(profile, post) do
    broadcast(profile, :post_created, %{post_id: post.id})
  end

  def broadcast_story_created(profile, story) do
    broadcast(profile, :story_created, %{story_id: story.id})
  end

  defp broadcast(profile, type, attrs) do
    event =
      Map.merge(attrs, %{
        type: type,
        profile_id: profile.id,
        user_id: profile.user_id,
        username: profile.instagram_username,
        at: DateTime.utc_now(:second)
      })

    Phoenix.PubSub.broadcast(
      Instabot.PubSub,
      topic(profile.user_id),
      {:instagram_event, event}
    )

    event
  end

  defp topic(user_id), do: "instagram_updates:#{user_id}"
end
