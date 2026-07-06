# frozen_string_literal: true

require "test_helper"

module Workflows
  # Runs the real workflow end to end through the SDK time-skipping WorkflowEnvironment
  # (docs/testing.md §2 Temporal-workflow target) with a fake activity registered on the
  # worker — instead of stubbing execute_activity on the instance. Time-skipping fast-
  # forwards retry backoff, so the retry-policy behavior is exercised without real waits.
  class AgentTokenRefreshWorkflowTest < ActiveSupport::TestCase
    TASK_QUEUE = "agent-token-refresh-test"

    # Fake stand-in for Activities::AgentCredentials::RefreshExpiringTokensActivity,
    # registered under the real activity name the workflow dispatches to.
    class FakeRefreshActivity < Temporalio::Activity::Definition
      activity_name "agent_credentials_refresh_expiring_tokens_activity"
      def execute(_input = nil)
        { refreshed: 3, not_needed: 1, errors: 0 }
      end
    end

    # Fails on the first attempt, succeeds on the second — proves the retry policy.
    class FlakyRefreshActivity < Temporalio::Activity::Definition
      activity_name "agent_credentials_refresh_expiring_tokens_activity"
      @attempts = 0
      class << self
        attr_accessor :attempts
      end
      def execute(_input = nil)
        self.class.attempts += 1
        raise "transient failure" if self.class.attempts < 2

        { refreshed: 0, not_needed: 0, errors: 0 }
      end
    end

    setup do
      # The workflow resolves activities from the class-level registry proxy; point the
      # one activity it calls at our test task queue.
      proxy = Object.new
      proxy.define_singleton_method(:agent_credentials_refresh_expiring_tokens_activity) do
        TemporalWorkflowHelper::ActivityRef.new("agent_credentials_refresh_expiring_tokens_activity", TASK_QUEUE)
      end
      AgentTokenRefreshWorkflow.stubs(:_preloaded_activities).returns(proxy)
    end

    test "executes the refresh activity and returns its counts" do
      result = run_workflow(AgentTokenRefreshWorkflow,
                            activities: [ FakeRefreshActivity.new ], task_queue: TASK_QUEUE)

      assert_equal 3, result["refreshed"]
      assert_equal 1, result["not_needed"]
      assert_equal 0, result["errors"]
    end

    test "retries the activity under the max_attempts:2 policy (time-skips the backoff)" do
      FlakyRefreshActivity.attempts = 0

      result = run_workflow(AgentTokenRefreshWorkflow,
                            activities: [ FlakyRefreshActivity.new ], task_queue: TASK_QUEUE)

      assert_equal 2, FlakyRefreshActivity.attempts, "activity should be retried exactly once"
      assert_equal 0, result["refreshed"]
    end
  end
end
