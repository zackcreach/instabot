defmodule Instabot.Instagram.ScrapeLog do
  @moduledoc false
  use Instabot.Schema, prefix: "slg"

  import Ecto.Changeset

  @scrape_types ~w(posts stories)
  @statuses ~w(started completed failed)

  schema "scrape_logs" do
    field :scrape_type, :string
    field :status, :string, default: "started"
    field :posts_found, :integer, default: 0
    field :stories_found, :integer, default: 0
    field :error_message, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :tracked_profile, Instabot.Instagram.TrackedProfile, type: UXID

    timestamps(type: :utc_datetime)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :scrape_type,
      :status,
      :posts_found,
      :stories_found,
      :error_message,
      :started_at,
      :completed_at
    ])
    |> validate_required([:scrape_type, :tracked_profile_id])
    |> validate_inclusion(:scrape_type, @scrape_types)
    |> validate_inclusion(:status, @statuses)
  end
end
