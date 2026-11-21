# frozen_string_literal: true

require "time"

# The arithmetic behind bin/ci-timings: per-job duration and queue wait, and the wall clock of a
# run, over a set of finished CI runs. Plain Ruby with no gems, so the script runs on a bare
# machine with only `gh`.
#
# A run is `{ "created_at" => iso8601, "jobs" => [job, ...] }` where a job is the object the
# Actions API returns (`name`, `conclusion`, `created_at`, `started_at`, `completed_at`, `steps`).
module CiTimings
  Report = Struct.new(:run_count, :wall_clocks, :jobs, keyword_init: true)
  JobStats = Struct.new(:durations, :queue_waits, :steps, keyword_init: true)

  module_function

  def median(values)
    sorted = values.sort
    middle = sorted.size / 2
    sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
  end

  # Nearest rank: the smallest value with at least `fraction` of the values at or below it.
  def percentile(values, fraction)
    sorted = values.sort
    sorted[[ (sorted.size * fraction).ceil - 1, 0 ].max]
  end

  def seconds(from, to)
    Time.parse(to) - Time.parse(from)
  end

  # Only jobs and steps that succeeded count: a skipped job has no duration worth a median, and a
  # failed one stopped early.
  def summarize(runs)
    wall_clocks = []
    jobs = Hash.new { |hash, name| hash[name] = JobStats.new(durations: [], queue_waits: [], steps: Hash.new { |inner, step| inner[step] = [] }) }

    runs.each do |run|
      finished = run["jobs"].select { |job| job["conclusion"] == "success" && job["completed_at"] }
      next if finished.empty?

      # From the run's creation, so the queue before the first job starts is part of it.
      wall_clocks << seconds(run["created_at"], finished.map { |job| job["completed_at"] }.max)
      finished.each { |job| add_job(jobs[job["name"]], job) }
    end

    Report.new(run_count: runs.size, wall_clocks: wall_clocks, jobs: jobs)
  end

  def add_job(stats, job)
    stats.durations << seconds(job["started_at"], job["completed_at"])
    # Time between the job being queued and a runner picking it up.
    stats.queue_waits << seconds(job["created_at"], job["started_at"])
    job["steps"].each do |step|
      next unless step["conclusion"] == "success" && step["started_at"] && step["completed_at"]

      stats.steps[step["name"]] << seconds(step["started_at"], step["completed_at"])
    end
  end

  def render(report, step_threshold:)
    lines = []
    lines << format("wall clock of a run, creation to last job end: median %ds, p90 %ds, longest %ds",
                    median(report.wall_clocks), percentile(report.wall_clocks, 0.9), report.wall_clocks.max)
    lines << ""
    lines << format("%-40s %4s %7s %7s %7s %9s", "job", "runs", "median", "p90", "max", "queue med")
    report.jobs.sort_by { |_name, stats| -median(stats.durations) }.each do |name, stats|
      lines << format("%-40s %4d %6ds %6ds %6ds %8ds", name, stats.durations.size, median(stats.durations),
                      percentile(stats.durations, 0.9), stats.durations.max, median(stats.queue_waits))
      stats.steps.each do |step, values|
        lines << format("    %-36s %4d %6ds", step, values.size, median(values)) if median(values) >= step_threshold
      end
    end
    lines.join("\n")
  end
end
