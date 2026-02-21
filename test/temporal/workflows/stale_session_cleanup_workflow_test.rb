# frozen_string_literal: true

require "test_helper"

module Workflows
  class StaleSessionCleanupWorkflowTest < ActiveSupport::TestCase
    setup do
      @workflow = StaleSessionCleanupWorkflow.new

      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:error)
    end

    test "executes cleanup activity and returns result" do
      expected_result = { cleaned_running: 2, cleaned_ready: 1 }

      activities = mock("activities")
      activities.stubs(:session_cleanup_stale_activity).returns(:session_cleanup_stale_activity)

      @workflow.stubs(:activities).returns(activities)
      @workflow.stubs(:execute_activity)
        .with(:session_cleanup_stale_activity, {}, has_entries(start_to_close_timeout: 300))
        .returns(expected_result)

      result = @workflow.run

      assert_equal 2, result[:cleaned_running]
      assert_equal 1, result[:cleaned_ready]
    end

    test "uses limited retry policy" do
      activities = mock("activities")
      activities.stubs(:session_cleanup_stale_activity).returns(:session_cleanup_stale_activity)

      @workflow.stubs(:activities).returns(activities)

      retry_policy = nil
      @workflow.stubs(:execute_activity).with do |_act, _input, opts|
        retry_policy = opts[:retry_policy]
        true
      end.returns({})

      @workflow.run

      assert_instance_of Temporalio::RetryPolicy, retry_policy
      assert_equal 2, retry_policy.max_attempts
    end
  end
end
