defmodule Instabot.Workers.SendDailyDigestsTest do
  use Instabot.DataCase, async: true
  use Oban.Testing, repo: Instabot.Repo

  import Instabot.AccountsFixtures

  alias Instabot.Notifications
  alias Instabot.Workers.SendDailyDigests
  alias Instabot.Workers.SendDigest

  describe "perform/1" do
    test "enqueues SendDigest for users whose daily_send_at matches current hour" do
      user = user_fixture()
      current_hour = Time.utc_now().hour
      pref = Notifications.get_or_create_preference(user.id)

      {:ok, _} =
        Notifications.update_preference(pref, %{
          frequency: "daily",
          daily_send_at: Time.new!(current_hour, 0, 0)
        })

      assert :ok == SendDailyDigests.perform(%Oban.Job{})

      assert_enqueued(worker: SendDigest, args: %{user_id: user.id, digest_type: "daily"})
    end

    test "skips users whose daily_send_at does not match current hour" do
      user = user_fixture()
      other_hour = rem(Time.utc_now().hour + 6, 24)
      pref = Notifications.get_or_create_preference(user.id)

      {:ok, _} =
        Notifications.update_preference(pref, %{
          frequency: "daily",
          daily_send_at: Time.new!(other_hour, 0, 0)
        })

      assert :ok == SendDailyDigests.perform(%Oban.Job{})

      refute_enqueued(worker: SendDigest, args: %{user_id: user.id, digest_type: "daily"})
    end

    test "skips users without daily_send_at set" do
      user = user_fixture()
      pref = Notifications.get_or_create_preference(user.id)
      {:ok, _} = Notifications.update_preference(pref, %{frequency: "daily"})

      assert :ok == SendDailyDigests.perform(%Oban.Job{})

      refute_enqueued(worker: SendDigest, args: %{user_id: user.id, digest_type: "daily"})
    end
  end
end
