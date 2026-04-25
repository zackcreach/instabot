defmodule InstabotWeb.PageController do
  use InstabotWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
