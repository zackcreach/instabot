defmodule Instabot.Workers.SendWeeklyDigestsTest do
  use Instabot.DataCase, async: true
  use Oban.Testing, repo: Instabot.Repo

  import Instabot.AccountsFixtures

  alias Instabot.Notifications
  alias Instabot.Workers.SendDigest
  alias Instabot.Workers.SendWeeklyDigests

  describe "perform/1" do
    test "enqueues SendDigest for users whose weekly_send_day matches today" do
      user = user_fixture()
      today = Date.day_of_week(Date.utc_today())
      pref = Notifications.get_or_create_preference(user.id)

      {:ok, _} =
        Notifications.update_preference(pref, %{
          frequency: "weekly",
          weekly_send_day: today
        })

      assert :ok == SendWeeklyDigests.perform(%Oban.Job{})

      assert_enqueued(worker: SendDigest, args: %{user_id: user.id, digest_type: "weekly"})
    end

    test "skips users whose weekly_send_day does not match today" do
      user = user_fixture()
      today = Date.day_of_week(Date.utc_today())
      other_day = rem(today, 7) + 1
      pref = Notifications.get_or_create_preference(user.id)

      {:ok, _} =
        Notifications.update_preference(pref, %{
          frequency: "weekly",
          weekly_send_day: other_day
        })

      assert :ok == SendWeeklyDigests.perform(%Oban.Job{})

      refute_enqueued(worker: SendDigest, args: %{user_id: user.id, digest_type: "weekly"})
    end
  end
end
