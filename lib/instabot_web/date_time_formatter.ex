defmodule InstabotWeb.DateTimeFormatter do
  @moduledoc false

  @eastern_time_zone "America/New_York"

  def date(nil), do: ""

  def date(%DateTime{} = datetime) do
    datetime
    |> shift_to_eastern()
    |> Calendar.strftime("%b %d, %Y")
  end

  def long_date(nil), do: ""

  def long_date(%DateTime{} = datetime) do
    datetime
    |> shift_to_eastern()
    |> Calendar.strftime("%B %d, %Y")
  end

  def datetime(nil), do: ""

  def datetime(%DateTime{} = datetime) do
    datetime
    |> shift_to_eastern()
    |> Calendar.strftime("%b %d, %Y %I:%M %p")
  end

  def long_datetime(nil), do: ""

  def long_datetime(%DateTime{} = datetime) do
    datetime
    |> shift_to_eastern()
    |> Calendar.strftime("%B %d, %Y at %I:%M %p")
  end

  def relative(nil), do: "just now"

  def relative(%DateTime{} = datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 2_592_000 -> "#{div(diff, 86_400)}d ago"
      true -> date(datetime)
    end
  end

  def short_relative(nil), do: "just now"

  def short_relative(%DateTime{} = datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp shift_to_eastern(datetime) do
    case DateTime.shift_zone(datetime, @eastern_time_zone) do
      {:ok, eastern_datetime} -> eastern_datetime
      {:error, _reason} -> datetime
    end
  end
end
