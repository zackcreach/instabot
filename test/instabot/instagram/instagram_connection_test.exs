defmodule Instabot.Instagram.InstagramConnectionTest do
  use ExUnit.Case, async: true

  alias Instabot.Instagram.InstagramConnection

  test "does not define persistent password storage" do
    refute :encrypted_password in InstagramConnection.__schema__(:fields)
  end
end
