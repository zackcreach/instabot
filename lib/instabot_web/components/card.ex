defmodule InstabotWeb.Card do
  @moduledoc """
  Card component for wrapping content in a styled container.
  """
  use Phoenix.Component

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def render(assigns) do
    ~H"""
    <div class={["card bg-base-100 shadow-lg p-8", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
