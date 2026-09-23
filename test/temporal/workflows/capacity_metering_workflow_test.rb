# frozen_string_literal: true

require "test_helper"

module Workflows
  # Runs the real workflow end to end through the SDK time-skipping
  # WorkflowEnvironment (docs/testing.md §2 Temporal-workflow target) with a fake
  # activity registered on the worker.
  class CapacityMeteringWorkflowTest < ActiveSupport::TestCase
    TASK_QUEUE = "capacity-metering-test"

    class FakeReportActivity < Temporalio::Activity::Definition
      activity_name "billing_report_capacity_activity"
      def execute(_input = nil)
        { provider: "recording", sent: 2, failed: 0 }
      end
    end

    # Counts its attempts so the single-attempt policy can be proven rather than
    # assumed — a retry here bills an AWS Marketplace customer twice.
    class CountingFailingActivity < Temporalio::Activity::Definition
      activity_name "billing_report_capacity_activity"
      @attempts = 0
      class << self
        attr_accessor :attempts
      end
      def execute(_input = nil)
        self.class.attempts += 1
        raise "provider is down"
      end
    end

    setup do
      proxy = Object.new
      proxy.define_singleton_method(:billing_report_capacity_activity) do
        TemporalWorkflowHelper::ActivityRef.new("billing_report_capacity_activity", TASK_QUEUE)
      end
      CapacityMeteringWorkflow.stubs(:_preloaded_activities).returns(proxy)
    end

    test "executes the reporting activity and returns its summary" do
      result = run_workflow(CapacityMeteringWorkflow,
                            activities: [ FakeReportActivity.new ], task_queue: TASK_QUEUE)

      assert_equal 2, result["sent"]
      assert_equal 0, result["failed"]
    end

    # AWS Marketplace counts one record per hour PER POD, so a retry landing on
    # another replica finds a fresh budget and emits a second record for the same
    # hour. The ledger recovers a failed send on the next run; the activity must
    # never be retried inside one.
    test "never retries the activity, because a retry would bill the hour twice" do
      CountingFailingActivity.attempts = 0

      assert_raises(Temporalio::Error::WorkflowFailedError) do
        run_workflow(CapacityMeteringWorkflow,
                     activities: [ CountingFailingActivity.new ], task_queue: TASK_QUEUE)
      end

      assert_equal 1, CountingFailingActivity.attempts
    end
  end
end
