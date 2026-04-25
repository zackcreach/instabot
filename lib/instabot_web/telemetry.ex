defmodule InstabotWeb.Telemetry do
  @moduledoc false
  use Supervisor

  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("instabot.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("instabot.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("instabot.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("instabot.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("instabot.repo.query.idle_time",
        unit: {:native, :millisecond},
        description: "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Oban Metrics
      counter("oban.job.stop",
        tags: [:worker, :queue],
        description: "Count of completed Oban jobs"
      ),
      counter("oban.job.exception",
        tags: [:worker, :queue],
        description: "Count of failed Oban jobs"
      ),
      summary("oban.job.stop.duration",
        tags: [:worker, :queue],
        unit: {:native, :millisecond},
        description: "Oban job execution time"
      ),
      summary("oban.job.stop.queue_time",
        tags: [:worker, :queue],
        unit: {:native, :millisecond},
        description: "Time Oban jobs waited in queue"
      ),

      # Application Metrics
      last_value("instabot.tracked_profiles.count",
        description: "Number of tracked Instagram profiles"
      )
    ]
  end

  def measure_tracked_profiles_count do
    count = Instabot.Repo.aggregate(Instabot.Instagram.TrackedProfile, :count)
    :telemetry.execute([:instabot, :tracked_profiles], %{count: count}, %{})
  rescue
    _ -> :ok
  end

  defp periodic_measurements do
    [{__MODULE__, :measure_tracked_profiles_count, []}]
  end
end
