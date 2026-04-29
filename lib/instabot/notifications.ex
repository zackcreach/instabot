defmodule Instabot.Notifications do
  @moduledoc """
  The Notifications context for managing user notification preferences and email digests.
  """

  import Ecto.Query

  alias Instabot.Notifications.EmailDigest
  alias Instabot.Notifications.NotificationPreference
  alias Instabot.Notifications.ProfileNotificationPreference
  alias Instabot.Repo

  @boolean_override_fields [:include_images, :include_ocr]

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

  def get_profile_preference_for_profile(tracked_profile_id) do
    Repo.get_by(ProfileNotificationPreference, tracked_profile_id: tracked_profile_id)
  end

  def get_or_create_profile_preference(user_id, tracked_profile_id) do
    case get_profile_preference_for_profile(tracked_profile_id) do
      %ProfileNotificationPreference{} = preference ->
        preference

      nil ->
        %ProfileNotificationPreference{user_id: user_id, tracked_profile_id: tracked_profile_id}
        |> ProfileNotificationPreference.changeset(%{frequency: "inherit"})
        |> Repo.insert(
          on_conflict: :nothing,
          conflict_target: :tracked_profile_id,
          returning: true
        )
        |> case do
          {:ok, preference} -> preference
          {:error, _changeset} -> get_profile_preference_for_profile(tracked_profile_id)
        end
    end
  end

  def change_profile_preference(%ProfileNotificationPreference{} = preference, attrs \\ %{}) do
    ProfileNotificationPreference.changeset(preference, attrs)
  end

  def update_profile_preference(%ProfileNotificationPreference{} = preference, attrs) do
    preference
    |> ProfileNotificationPreference.changeset(attrs)
    |> Repo.update()
  end

  def effective_profile_preference(user_id, tracked_profile_id) do
    user_preference = get_or_create_preference(user_id)
    profile_preference = get_or_create_profile_preference(user_id, tracked_profile_id)

    resolve_effective_profile_preference(user_preference, profile_preference)
  end

  def resolve_effective_profile_preference(%NotificationPreference{} = user_preference, profile_preference) do
    profile_preference = profile_preference || %ProfileNotificationPreference{}

    user_preference
    |> Map.take([:frequency, :daily_send_at, :weekly_send_day, :email_address, :include_images, :include_ocr])
    |> Map.merge(%{
      frequency: effective_frequency(user_preference, profile_preference),
      include_images: effective_boolean(:include_images, user_preference, profile_preference),
      include_ocr: effective_boolean(:include_ocr, user_preference, profile_preference),
      user_preference: user_preference,
      profile_preference: profile_preference
    })
  end

  def list_profile_preferences_for_user(user_id) do
    ProfileNotificationPreference
    |> where(user_id: ^user_id)
    |> preload(:tracked_profile)
    |> Repo.all()
  end

  def due_profile_digest_jobs(frequency, due_at) do
    Instabot.Instagram.TrackedProfile
    |> where(is_active: true)
    |> preload([:user, :profile_notification_preference])
    |> Repo.all()
    |> Enum.map(&profile_digest_job(&1, frequency, due_at))
    |> Enum.reject(&is_nil/1)
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
    |> where([digest], is_nil(digest.tracked_profile_id))
    |> order_by(desc: :sent_at)
    |> limit(1)
    |> Repo.one()
  end

  def last_digest_for_profile(user_id, digest_type, tracked_profile_id) do
    EmailDigest
    |> where(user_id: ^user_id, digest_type: ^digest_type, tracked_profile_id: ^tracked_profile_id)
    |> order_by(desc: :sent_at)
    |> limit(1)
    |> Repo.one()
  end

  defp profile_digest_job(profile, frequency, due_at) do
    user_preference = get_or_create_preference(profile.user_id)
    profile_preference = profile.profile_notification_preference
    effective_preference = resolve_effective_profile_preference(user_preference, profile_preference)

    with true <- effective_preference.frequency == frequency,
         true <- due_for_frequency?(user_preference, frequency, due_at) do
      %{
        user_id: profile.user_id,
        tracked_profile_id: profile.id,
        preference: effective_preference
      }
    else
      _not_due -> nil
    end
  end

  defp due_for_frequency?(%{daily_send_at: %Time{} = daily_send_at}, "daily", %Time{} = due_at) do
    daily_send_at.hour == due_at.hour
  end

  defp due_for_frequency?(%{weekly_send_day: weekly_send_day}, "weekly", %Date{} = due_at) do
    weekly_send_day == Date.day_of_week(due_at)
  end

  defp due_for_frequency?(_user_preference, _frequency, _due_at), do: false

  defp effective_frequency(_user_preference, %{frequency: frequency})
       when frequency in ["immediate", "daily", "weekly", "disabled"] do
    frequency
  end

  defp effective_frequency(user_preference, _profile_preference), do: user_preference.frequency

  defp effective_boolean(field, user_preference, profile_preference) when field in @boolean_override_fields do
    case Map.get(profile_preference, field) do
      value when is_boolean(value) -> value
      _inherit -> Map.fetch!(user_preference, field)
    end
  end
end
