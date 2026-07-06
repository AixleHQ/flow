# frozen_string_literal: true

require "test_helper"

module Workflows
  # Runs the real workflow end to end through the SDK time-skipping WorkflowEnvironment
  # (docs/testing.md §2 Temporal-workflow target) with a fake activity registered on the
  # worker — instead of stubbing execute_activity on the instance. Time-skipping fast-
  # forwards retry backoff, so the retry-policy behavior is exercised without real waits.
  class StaleSessionCleanupWorkflowTest < ActiveSupport::TestCase
    TASK_QUEUE = "stale-session-cleanup-test"

    # Fake stand-in for Activities::Session::CleanupStaleActivity, registered on the
    # worker under the real activity name the workflow dispatches to.
    class FakeCleanupActivity < Temporalio::Activity::Definition
      activity_name "session_cleanup_stale_activity"
      def execute(_input = nil)
        { cleaned_running: 2, cleaned_ready: 1 }
      end
    end

    # Fails on the first attempt, succeeds on the second — proves the retry policy.
    class FlakyCleanupActivity < Temporalio::Activity::Definition
      activity_name "session_cleanup_stale_activity"
      @attempts = 0
      class << self
        attr_accessor :attempts
      end
      def execute(_input = nil)
        self.class.attempts += 1
        raise "transient failure" if self.class.attempts < 2

        { cleaned_running: 0, cleaned_ready: 0 }
      end
    end

    setup do
      # The workflow resolves activities from the class-level registry proxy; point the
      # one activity it calls at our test task queue.
      proxy = Object.new
      proxy.define_singleton_method(:session_cleanup_stale_activity) do
        TemporalWorkflowHelper::ActivityRef.new("session_cleanup_stale_activity", TASK_QUEUE)
      end
      StaleSessionCleanupWorkflow.stubs(:_preloaded_activities).returns(proxy)
    end

    test "executes the cleanup activity and returns its result" do
      result = run_workflow(StaleSessionCleanupWorkflow,
                            activities: [ FakeCleanupActivity.new ], task_queue: TASK_QUEUE)

      assert_equal 2, result["cleaned_running"]
      assert_equal 1, result["cleaned_ready"]
    end

    test "retries the activity under the max_attempts:2 policy (time-skips the backoff)" do
      FlakyCleanupActivity.attempts = 0

      result = run_workflow(StaleSessionCleanupWorkflow,
                            activities: [ FlakyCleanupActivity.new ], task_queue: TASK_QUEUE)

      assert_equal 2, FlakyCleanupActivity.attempts, "activity should be retried exactly once"
      assert_equal 0, result["cleaned_running"]
    end
  end
end
