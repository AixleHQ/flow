# frozen_string_literal: true

require "test_helper"

module Workflows
  # Runs the real workflow end to end through the SDK time-skipping
  # WorkflowEnvironment with a fake activity registered on the worker.
  class UsageRollupWorkflowTest < ActiveSupport::TestCase
    TASK_QUEUE = "usage-rollup-test"

    class EchoActivity < Temporalio::Activity::Definition
      activity_name "usage_rollup_hours_activity"
      def execute(input = nil)
        { "received" => input }
      end
    end

    # Fails twice, then succeeds: the rollup rewrites only its own rows, so a
    # retry is safe and expected.
    class FlakyActivity < Temporalio::Activity::Definition
      activity_name "usage_rollup_hours_activity"
      @attempts = 0
      class << self
        attr_accessor :attempts
      end
      def execute(_input = nil)
        self.class.attempts += 1
        raise "database went away" if self.class.attempts < 3

        { "rows" => 1 }
      end
    end

    setup do
      proxy = Object.new
      proxy.define_singleton_method(:usage_rollup_hours_activity) do
        TemporalWorkflowHelper::ActivityRef.new("usage_rollup_hours_activity", TASK_QUEUE)
      end
      UsageRollupWorkflow.stubs(:_preloaded_activities).returns(proxy)
    end

    test "the schedule's run passes no range, so the activity measures the last closed hours" do
      result = run_workflow(UsageRollupWorkflow, activities: [ EchoActivity.new ], task_queue: TASK_QUEUE)

      assert_equal({}, result["received"])
    end

    test "a recompute passes its range through" do
      result = run_workflow(UsageRollupWorkflow, { "from_hour" => "2026-09-25T00:00:00Z" },
                            activities: [ EchoActivity.new ], task_queue: TASK_QUEUE)

      assert_equal({ "from_hour" => "2026-09-25T00:00:00Z" }, result["received"])
    end

    test "a failed attempt is retried" do
      FlakyActivity.attempts = 0

      result = run_workflow(UsageRollupWorkflow, activities: [ FlakyActivity.new ], task_queue: TASK_QUEUE)

      assert_equal 1, result["rows"]
      assert_equal 3, FlakyActivity.attempts
    end
  end
end
