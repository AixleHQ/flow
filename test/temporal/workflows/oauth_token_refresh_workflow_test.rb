# frozen_string_literal: true

require "test_helper"

module Workflows
  # Runs the real workflow end to end through the SDK time-skipping WorkflowEnvironment
  # (docs/testing.md §2) with a fake activity registered on the worker. Time-skipping
  # fast-forwards retry backoff so the retry-policy behavior needs no real waits.
  class OauthTokenRefreshWorkflowTest < ActiveSupport::TestCase
    TASK_QUEUE = "oauth-token-refresh-test"

    class FakeRefreshActivity < Temporalio::Activity::Definition
      activity_name "oauth_refresh_expiring_tokens_activity"
      def execute(_input = nil)
        { refreshed: 2, not_needed: 5, errors: 1 }
      end
    end

    # Fails once, succeeds on the second attempt — proves the retry policy.
    class FlakyRefreshActivity < Temporalio::Activity::Definition
      activity_name "oauth_refresh_expiring_tokens_activity"
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
      proxy = Object.new
      proxy.define_singleton_method(:oauth_refresh_expiring_tokens_activity) do
        TemporalWorkflowHelper::ActivityRef.new("oauth_refresh_expiring_tokens_activity", TASK_QUEUE)
      end
      OauthTokenRefreshWorkflow.stubs(:_preloaded_activities).returns(proxy)
    end

    test "executes the refresh activity and returns its counts" do
      result = run_workflow(OauthTokenRefreshWorkflow,
                            activities: [ FakeRefreshActivity.new ], task_queue: TASK_QUEUE)

      assert_equal 2, result["refreshed"]
      assert_equal 5, result["not_needed"]
      assert_equal 1, result["errors"]
    end

    test "retries the activity under the max_attempts:2 policy (time-skips the backoff)" do
      FlakyRefreshActivity.attempts = 0

      result = run_workflow(OauthTokenRefreshWorkflow,
                            activities: [ FlakyRefreshActivity.new ], task_queue: TASK_QUEUE)

      assert_equal 2, FlakyRefreshActivity.attempts, "activity should be retried exactly once"
      assert_equal 0, result["refreshed"]
    end
  end
end
