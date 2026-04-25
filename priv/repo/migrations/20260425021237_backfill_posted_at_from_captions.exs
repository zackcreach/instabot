defmodule Instabot.Repo.Migrations.BackfillPostedAtFromCaptions do
  use Ecto.Migration

  @month_numbers %{
    "January" => 1,
    "February" => 2,
    "March" => 3,
    "April" => 4,
    "May" => 5,
    "June" => 6,
    "July" => 7,
    "August" => 8,
    "September" => 9,
    "October" => 10,
    "November" => 11,
    "December" => 12
  }

  def change do
    execute(&backfill_posted_at_from_captions/0, fn -> :ok end)
  end

  defp backfill_posted_at_from_captions do
    repo().query!("""
    SELECT id, caption
    FROM posts
    WHERE posted_at IS NULL
      AND caption IS NOT NULL
    """)
    |> Map.fetch!(:rows)
    |> Enum.each(&backfill_post/1)
  end

  defp backfill_post([id, caption]) do
    with [_, month_name, day, year] <-
           Regex.run(~r/\bon\s+([A-Z][a-z]+)\s+(\d{1,2}),\s+(\d{4})\s*:/, caption),
         month when is_integer(month) <- @month_numbers[month_name],
         {day_number, ""} <- Integer.parse(day),
         {year_number, ""} <- Integer.parse(year),
         {:ok, naive_datetime} <- NaiveDateTime.new(year_number, month, day_number, 12, 0, 0) do
      repo().query!("UPDATE posts SET posted_at = $1 WHERE id = $2", [naive_datetime, id])
    end
  end
end
