defmodule Instabot.Notifications do
  @moduledoc """
  The Notifications context for managing user notification preferences and email digests.
  """

  import Ecto.Query

  alias Instabot.Notifications.EmailDigest
  alias Instabot.Notifications.NotificationPreference
  alias Instabot.Repo

  def get_preference_for_user(user_id) do
    Repo.get_by(NotificationPreference, user_id: user_id)
  end

  def get_or_create_preference(user_id) do
    case get_preference_for_user(user_id) do
      %NotificationPreference{} = pref ->
        pref

      nil ->
        %NotificationPreference{user_id: user_id}
        |> NotificationPreference.changeset(%{frequency: "disabled"})
        |> Repo.insert(
          on_conflict: :nothing,
          conflict_target: :user_id,
          returning: true
        )
        |> case do
          {:ok, pref} -> pref
          {:error, _changeset} -> get_preference_for_user(user_id)
        end
    end
  end

  def update_preference(%NotificationPreference{} = preference, attrs) do
    preference
    |> NotificationPreference.changeset(attrs)
    |> Repo.update()
  end

  def change_preference(%NotificationPreference{} = preference, attrs \\ %{}) do
    NotificationPreference.changeset(preference, attrs)
  end

  def list_preferences_by_frequency(frequency) do
    NotificationPreference
    |> where(frequency: ^frequency)
    |> preload(:user)
    |> Repo.all()
  end

  def create_email_digest(user_id, attrs) do
    %EmailDigest{user_id: user_id}
    |> EmailDigest.changeset(attrs)
    |> Repo.insert()
  end

  def disable_notifications(user_id) do
    preference = get_or_create_preference(user_id)
    update_preference(preference, %{frequency: "disabled"})
  end

  def last_digest_for_user(user_id, digest_type) do
    EmailDigest
    |> where(user_id: ^user_id, digest_type: ^digest_type)
    |> order_by(desc: :sent_at)
    |> limit(1)
    |> Repo.one()
  end
end
