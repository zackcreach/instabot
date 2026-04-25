defmodule Instabot.Scraper.SessionTest do
  use Instabot.DataCase

  import Instabot.AccountsFixtures
  import Instabot.InstagramFixtures

  alias Instabot.Encryption
  alias Instabot.Instagram
  alias Instabot.Scraper.Session

  describe "decrypt_cookies (via setup_session error path)" do
    test "returns error when connection has no cookies" do
      user = user_fixture()
      connection = instagram_connection_fixture(user)

      fake_browser = spawn(fn -> Process.sleep(:infinity) end)

      assert {:error, :no_cookies} = Session.setup_session(fake_browser, connection)

      Process.exit(fake_browser, :kill)
    end
  end

  describe "save_cookies/3 integration" do
    test "encrypts and stores cookies via the Instagram context" do
      user = user_fixture()
      connection = instagram_connection_fixture(user)

      encrypted = Encryption.encrypt_term(sample_cookies())
      {:ok, connection} = Instagram.store_cookies(connection, encrypted, DateTime.utc_now())

      {:ok, decrypted} = Encryption.decrypt_term(connection.encrypted_cookies)
      assert is_list(decrypted)
      assert length(decrypted) == 2
    end
  end

  describe "connected_connection_fixture/2" do
    test "creates a connection with encrypted cookies" do
      user = user_fixture()
      connection = connected_connection_fixture(user)

      assert "connected" == connection.status
      assert nil != connection.encrypted_cookies

      {:ok, cookies} = Encryption.decrypt_term(connection.encrypted_cookies)
      assert is_list(cookies)

      cookie_names = Enum.map(cookies, & &1["name"])
      assert "sessionid" in cookie_names
      assert "csrftoken" in cookie_names
    end
  end
end
