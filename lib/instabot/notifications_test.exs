defmodule Instabot.NotificationsTest do
  use Instabot.DataCase, async: true

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Notifications

  describe "effective_profile_preference/2" do
    test "inherits account defaults when profile fields are unset" do
      user = user_fixture()
      profile = tracked_profile_fixture(user)
      user_preference = Notifications.get_or_create_preference(user.id)

      {:ok, _user_preference} =
        Notifications.update_preference(user_preference, %{
          frequency: "daily",
          include_images: false,
          include_ocr: true
        })

      assert %{
               frequency: "daily",
               include_images: false,
               include_ocr: true
             } = Notifications.effective_profile_preference(user.id, profile.id)
    end

    test "applies profile overrides independently" do
      user = user_fixture()
      profile = tracked_profile_fixture(user)
      user_preference = Notifications.get_or_create_preference(user.id)

      {:ok, _user_preference} =
        Notifications.update_preference(user_preference, %{
          frequency: "daily",
          include_images: false,
          include_ocr: true
        })

      profile_preference = Notifications.get_or_create_profile_preference(user.id, profile.id)

      {:ok, _profile_preference} =
        Notifications.update_profile_preference(profile_preference, %{
          frequency: "immediate",
          include_images: true,
          include_ocr: false
        })

      assert %{
               frequency: "immediate",
               include_images: true,
               include_ocr: false
             } = Notifications.effective_profile_preference(user.id, profile.id)
    end
  end
end
