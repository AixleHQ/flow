# frozen_string_literal: true

require "test_helper"

module Workflows
  class TrackerSubscriptionRefreshWorkflowTest < ActiveSupport::TestCase
    TASK_QUEUE = "tracker-subscription-refresh-test"

    class FakeRefreshActivity < Temporalio::Activity::Definition
      activity_name "trackers_refresh_subscriptions_activity"

      def execute(_input = nil)
        { refreshed: 3, renewed_grants: 1, errors: 0 }
      end
    end

    setup do
      proxy = Object.new
      proxy.define_singleton_method(:trackers_refresh_subscriptions_activity) do
        TemporalWorkflowHelper::ActivityRef.new("trackers_refresh_subscriptions_activity", TASK_QUEUE)
      end
      TrackerSubscriptionRefreshWorkflow.stubs(:_preloaded_activities).returns(proxy)
    end

    test "runs the sweep and returns its counts" do
      result = run_workflow(TrackerSubscriptionRefreshWorkflow, activities: [ FakeRefreshActivity.new ], task_queue: TASK_QUEUE)

      assert_equal [ 3, 1 ], result.values_at("refreshed", "renewed_grants")
    end
  end
end
