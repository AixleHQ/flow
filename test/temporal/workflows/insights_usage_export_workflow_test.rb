# frozen_string_literal: true

require "test_helper"

module Workflows
  # Runs the real workflow end to end through the SDK time-skipping
  # WorkflowEnvironment (docs/testing.md §2 Temporal-workflow target) with a fake
  # activity registered on the worker.
  class InsightsUsageExportWorkflowTest < ActiveSupport::TestCase
    TASK_QUEUE = "insights-usage-export-test"

    class FakeExportActivity < Temporalio::Activity::Definition
      activity_name "aixle_insights_export_usage_activity"
      def execute(_input = nil)
        { exported: 3, failed: 0, skipped: 1 }
      end
    end

    # Counts attempts so the single-attempt policy is proven, not assumed:
    # recovery is the next scheduled run replaying the ledger, not a retry here.
    class CountingFailingActivity < Temporalio::Activity::Definition
      activity_name "aixle_insights_export_usage_activity"
      @attempts = 0
      class << self
        attr_accessor :attempts
      end
      def execute(_input = nil)
        self.class.attempts += 1
        raise "collector is down"
      end
    end

    setup do
      proxy = Object.new
      proxy.define_singleton_method(:aixle_insights_export_usage_activity) do
        TemporalWorkflowHelper::ActivityRef.new("aixle_insights_export_usage_activity", TASK_QUEUE)
      end
      InsightsUsageExportWorkflow.stubs(:_preloaded_activities).returns(proxy)
    end

    test "executes the export activity and returns its summary" do
      result = run_workflow(InsightsUsageExportWorkflow,
                            activities: [ FakeExportActivity.new ], task_queue: TASK_QUEUE)

      assert_equal 3, result["exported"]
      assert_equal 0, result["failed"]
      assert_equal 1, result["skipped"]
    end

    test "never retries the activity, because recovery is the next run replaying the ledger" do
      CountingFailingActivity.attempts = 0

      assert_raises(Temporalio::Error::WorkflowFailedError) do
        run_workflow(InsightsUsageExportWorkflow,
                     activities: [ CountingFailingActivity.new ], task_queue: TASK_QUEUE)
      end

      assert_equal 1, CountingFailingActivity.attempts
    end
  end
end
