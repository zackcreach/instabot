defmodule Instabot.Workers.SendDailyDigestsTest do
  use Instabot.DataCase, async: true
  use Oban.Testing, repo: Instabot.Repo

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Notifications
  alias Instabot.Workers.SendDailyDigests
  alias Instabot.Workers.SendDigest

  describe "perform/1" do
    test "enqueues SendDigest for users whose daily_send_at matches current hour" do
      user = user_fixture()
      profile = tracked_profile_fixture(user)
      current_hour = Time.utc_now().hour
      pref = Notifications.get_or_create_preference(user.id)

      {:ok, _} =
        Notifications.update_preference(pref, %{
          frequency: "daily",
          daily_send_at: Time.new!(current_hour, 0, 0)
        })

      assert :ok == SendDailyDigests.perform(%Oban.Job{})

      assert_enqueued(
        worker: SendDigest,
        args: %{user_id: user.id, digest_type: "daily", tracked_profile_id: profile.id}
      )
    end

    test "skips users whose daily_send_at does not match current hour" do
      user = user_fixture()
      profile = tracked_profile_fixture(user)
      other_hour = rem(Time.utc_now().hour + 6, 24)
      pref = Notifications.get_or_create_preference(user.id)

      {:ok, _} =
        Notifications.update_preference(pref, %{
          frequency: "daily",
          daily_send_at: Time.new!(other_hour, 0, 0)
        })

      assert :ok == SendDailyDigests.perform(%Oban.Job{})

      refute_enqueued(
        worker: SendDigest,
        args: %{user_id: user.id, digest_type: "daily", tracked_profile_id: profile.id}
      )
    end

    test "skips users without daily_send_at set" do
      user = user_fixture()
      profile = tracked_profile_fixture(user)
      pref = Notifications.get_or_create_preference(user.id)
      {:ok, _} = Notifications.update_preference(pref, %{frequency: "daily"})

      assert :ok == SendDailyDigests.perform(%Oban.Job{})

      refute_enqueued(
        worker: SendDigest,
        args: %{user_id: user.id, digest_type: "daily", tracked_profile_id: profile.id}
      )
    end

    test "enqueues profile override when account frequency is disabled" do
      user = user_fixture()
      profile = tracked_profile_fixture(user)
      current_hour = Time.utc_now().hour
      user_preference = Notifications.get_or_create_preference(user.id)

      {:ok, _user_preference} =
        Notifications.update_preference(user_preference, %{
          frequency: "disabled",
          daily_send_at: Time.new!(current_hour, 0, 0)
        })

      profile_preference = Notifications.get_or_create_profile_preference(user.id, profile.id)
      {:ok, _profile_preference} = Notifications.update_profile_preference(profile_preference, %{frequency: "daily"})

      assert :ok == SendDailyDigests.perform(%Oban.Job{})

      assert_enqueued(
        worker: SendDigest,
        args: %{user_id: user.id, digest_type: "daily", tracked_profile_id: profile.id}
      )
    end
  end
end
