defmodule InstabotWeb.RouterTest do
  use ExUnit.Case, async: true

  test "does not expose LiveDashboard outside development" do
    assert :error ==
             Phoenix.Router.route_info(
               InstabotWeb.Router,
               "GET",
               "/admin/dashboard",
               "instabot.prominent.tools"
             )
  end
end
