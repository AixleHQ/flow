# frozen_string_literal: true

require "test_helper"

# A deploy replays every open execution's history on the new code; a change that
# makes the code issue different commands for a recorded history wedges every
# execution shaped like it. Recording and retiring histories:
# docs/architecture/temporal-versioning.md.
class HistoryReplayTest < ActiveSupport::TestCase
  RECORD = ENV["RECORD_TEMPORAL_HISTORIES"].presence

  test "every recorded history replays on the current workflow code" do
    fixtures = TemporalHistories.fixtures
    assert_not_empty fixtures

    failures = TemporalHistories.replay(fixtures).filter_map do |path, result|
      next unless result.replay_failure

      message = result.replay_failure.message
      "#{Pathname(path).relative_path_from(TemporalHistories::DIR)}: #{message[/\[TMPRL\d+\][^"]*/] || message}"
    end

    assert_empty failures, "Gate the change behind Temporalio::Workflow.patched — these histories no longer replay"
  end

  test "every scenario has a recorded history" do
    record_scenarios! if RECORD

    missing = TemporalHistories.scenarios.select { |scenario| scenario.recorded.empty? }.map do |scenario|
      "#{scenario.workflow_type}/#{scenario.name}"
    end
    assert_empty missing, "Record them: RECORD_TEMPORAL_HISTORIES=#{Date.current.iso8601} " \
                          "bin/rails test #{Pathname(__FILE__).relative_path_from(Rails.root)}"
  end

  private

  def record_scenarios!
    label = RECORD == "1" ? Date.current.iso8601 : RECORD
    only = ENV["TEMPORAL_HISTORY_SCENARIOS"].to_s.split(",").map(&:strip)
    TemporalHistories.scenarios.each do |scenario|
      next if only.any? && only.exclude?("#{scenario.workflow_type}/#{scenario.name}")

      TemporalHistories.record(scenario, label: label)
    end
  end
end
