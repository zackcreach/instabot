defmodule InstabotWeb.HealthControllerTest do
  use InstabotWeb.ConnCase, async: true

  test "GET /health returns 200 with ok status", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert %{"status" => "ok"} = json_response(conn, 200)
  end
end
