# frozen_string_literal: true

require "test_helper"

module Workflows
  # Runs the real workflow end to end through the SDK time-skipping
  # WorkflowEnvironment (docs/testing.md §2 Temporal-workflow target) with a fake
  # activity registered on the worker.
  class GateReconciliationWorkflowTest < ActiveSupport::TestCase
    TASK_QUEUE = "gate-reconciliation-test"

    # Stands in for Activities::Gates::ReconcileCiActivity, under the real activity
    # name the workflow dispatches to.
    class FakeReconcileActivity < Temporalio::Activity::Definition
      activity_name "gates_reconcile_ci_activity"
      def execute(_input = nil)
        { checked: 3, resolved: 1, stale: 1, waiting: 1, errors: 0 }
      end
    end

    # Fails on the first attempt, succeeds on the second — proves the retry policy.
    class FlakyReconcileActivity < Temporalio::Activity::Definition
      activity_name "gates_reconcile_ci_activity"
      @attempts = 0
      class << self
        attr_accessor :attempts
      end
      def execute(_input = nil)
        self.class.attempts += 1
        raise "transient failure" if self.class.attempts < 2

        { checked: 0, resolved: 0, stale: 0, waiting: 0, errors: 0 }
      end
    end

    setup do
      proxy = Object.new
      proxy.define_singleton_method(:gates_reconcile_ci_activity) do
        TemporalWorkflowHelper::ActivityRef.new("gates_reconcile_ci_activity", TASK_QUEUE)
      end
      GateReconciliationWorkflow.stubs(:_preloaded_activities).returns(proxy)
    end

    test "executes the reconciliation activity and returns its summary" do
      result = run_workflow(GateReconciliationWorkflow,
                            activities: [ FakeReconcileActivity.new ], task_queue: TASK_QUEUE)

      assert_equal 3, result["checked"]
      assert_equal 1, result["resolved"]
      assert_equal 1, result["stale"]
    end

    test "retries the activity under the max_attempts:2 policy (time-skips the backoff)" do
      FlakyReconcileActivity.attempts = 0

      result = run_workflow(GateReconciliationWorkflow,
                            activities: [ FlakyReconcileActivity.new ], task_queue: TASK_QUEUE)

      assert_equal 2, FlakyReconcileActivity.attempts, "activity should be retried exactly once"
      assert_equal 0, result["checked"]
    end
  end
end
