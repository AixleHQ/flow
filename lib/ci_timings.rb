# frozen_string_literal: true

require "time"

# The arithmetic behind bin/ci-timings: per-job duration and queue wait, and the wall clock of a
# run, over a set of finished CI runs. Plain Ruby with no gems, so the script runs on a bare
# machine with only `gh`.
#
# A sample is one successful attempt of a run: `{ "started_at" => iso8601, "jobs" => [job, ...] }`,
# where `started_at` is the attempt's `run_started_at` and a job is the object the Actions API
# returns for that attempt (`name`, `conclusion`, `created_at`, `started_at`, `completed_at`,
# `steps`). A re-run ("Re-run all jobs") keeps the run's `created_at`, so an attempt is measured
# from its own start; the first attempt starts at the run's creation.
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

  # The sample for one attempt of a run (`GET /actions/runs/{id}/attempts/{n}`) and its jobs
  # (`.../attempts/{n}/jobs`), or nil when the attempt did not succeed. The block returns the jobs,
  # and is called only for a successful attempt.
  def sample(attempt)
    return unless attempt["conclusion"] == "success"

    { "started_at" => attempt["run_started_at"], "jobs" => yield }
  end

  def seconds(from, to)
    Time.parse(to) - Time.parse(from)
  end

  # Only jobs and steps that succeeded count: a skipped job has no duration worth a median, and a
  # failed one stopped early.
  def summarize(samples)
    wall_clocks = []
    jobs = Hash.new { |hash, name| hash[name] = JobStats.new(durations: [], queue_waits: [], steps: Hash.new { |inner, step| inner[step] = [] }) }

    samples.each do |sample|
      finished = sample["jobs"].select { |job| job["conclusion"] == "success" && job["completed_at"] }
      next if finished.empty?

      # From the attempt's start, so the queue before its first job starts is part of it.
      wall_clocks << seconds(sample["started_at"], finished.map { |job| job["completed_at"] }.max)
      finished.each { |job| add_job(jobs[job["name"]], job) }
    end

    Report.new(run_count: samples.size, wall_clocks: wall_clocks, jobs: jobs)
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
    lines << format("wall clock of a run attempt, start to last job end: median %ds, p90 %ds, longest %ds",
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
