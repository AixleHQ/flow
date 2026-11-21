# frozen_string_literal: true

require "test_helper"

class CiTimingsTest < ActiveSupport::TestCase
  test "median of an odd count is the middle value and of an even count the mean of the two middle ones" do
    assert_equal 3, CiTimings.median([ 5, 1, 3 ])
    assert_in_delta 2.5, CiTimings.median([ 4, 1, 3, 2 ]), 0.001
  end

  test "p90 of ten values is the ninth, and of one value is that value" do
    assert_equal 9, CiTimings.percentile((1..10).to_a.shuffle, 0.9)
    assert_equal 7, CiTimings.percentile([ 7 ], 0.9)
  end

  test "a run's wall clock runs from its creation to its last successful job's end" do
    report = CiTimings.summarize([ run("10:00:00", [
      job("Rails", "10:00:20", "10:00:30", "10:05:30"),
      job("Lint", "10:00:05", "10:00:10", "10:02:10")
    ]) ])

    assert_equal [ 330.0 ], report.wall_clocks
  end

  test "a job's duration is start to end and its queue wait is creation to start" do
    report = CiTimings.summarize([ run("10:00:00", [ job("Rails", "10:00:00", "10:00:40", "10:05:40") ]) ])
    stats = report.jobs["Rails"]

    assert_equal [ 300.0 ], stats.durations
    assert_equal [ 40.0 ], stats.queue_waits
  end

  test "skipped and failed jobs and steps are left out of every figure" do
    skipped = job("Refresh Layer Cache", "10:00:00", "10:00:00", "10:00:00", conclusion: "skipped")
    failed = job("Vitest", "10:00:00", "10:00:05", "10:09:05", conclusion: "failure")
    ok = job("Lint", "10:00:00", "10:00:05", "10:02:05", steps: [
      step("Run check", "10:00:10", "10:02:00"),
      step("Tear down", "10:02:00", "10:02:05", conclusion: "failure"),
      step("Post", nil, nil, conclusion: "skipped")
    ])
    report = CiTimings.summarize([ run("10:00:00", [ skipped, failed, ok ]) ])

    assert_equal [ "Lint" ], report.jobs.keys
    assert_equal [ 125.0 ], report.wall_clocks
    assert_equal({ "Run check" => [ 110.0 ] }, report.jobs["Lint"].steps)
  end

  test "a run with no successful job adds no wall clock" do
    report = CiTimings.summarize([ run("10:00:00", [ job("Lint", "10:00:00", "10:00:05", "10:01:00", conclusion: "failure") ]) ])

    assert_empty report.wall_clocks
    assert_equal 1, report.run_count
  end

  test "the report lists jobs longest median first, with the steps over the threshold under their job" do
    runs = [ "10:02:00", "10:04:00", "10:06:00" ].map do |long_end|
      run("10:00:00", [
        job("Short", "10:00:00", "10:00:10", "10:01:10"),
        job("Long", "10:00:00", "10:00:20", long_end,
            steps: [ step("Tests", "10:00:20", "10:00:50"), step("Setup", "10:00:00", "10:00:03") ])
      ])
    end
    output = CiTimings.render(CiTimings.summarize(runs), step_threshold: 20)
    names = output.lines.map { |line| line.split.first }

    assert_operator names.index("Long"), :<, names.index("Short")
    assert_includes output, "Tests"
    assert_not_includes output, "Setup"
    assert_match(/median 240s/, output)
  end

  private

  def run(created, jobs)
    { "created_at" => stamp(created), "jobs" => jobs }
  end

  def job(name, created, started, completed, conclusion: "success", steps: [])
    { "name" => name, "conclusion" => conclusion, "created_at" => stamp(created),
      "started_at" => stamp(started), "completed_at" => stamp(completed), "steps" => steps }
  end

  def step(name, started, completed, conclusion: "success")
    { "name" => name, "conclusion" => conclusion, "started_at" => started && stamp(started), "completed_at" => completed && stamp(completed) }
  end

  def stamp(time)
    "2026-11-21T#{time}Z"
  end
end
