# frozen_string_literal: true

require "test_helper"

module Workflows
  # Runs the real workflow end to end through the SDK time-skipping
  # WorkflowEnvironment (docs/testing.md §2 Temporal-workflow target) with a fake
  # activity registered on the worker.
  class ContainerSweepOrphanedResourcesWorkflowTest < ActiveSupport::TestCase
    TASK_QUEUE = "container-orphan-sweep-test"

    # Stands in for Activities::Container::SweepOrphanedResourcesActivity, under
    # the real activity name the workflow dispatches to.
    class FakeSweepActivity < Temporalio::Activity::Definition
      activity_name "container_sweep_orphaned_resources_activity"
      def execute(_input = nil)
        { reaped: 4, sessions: 1, kept_live: 2, failed: 0 }
      end
    end

    # Fails on the first attempt, succeeds on the second — proves the retry policy.
    class FlakySweepActivity < Temporalio::Activity::Definition
      activity_name "container_sweep_orphaned_resources_activity"
      @attempts = 0
      class << self
        attr_accessor :attempts
      end
      def execute(_input = nil)
        self.class.attempts += 1
        raise "transient failure" if self.class.attempts < 2

        { reaped: 0, sessions: 0, kept_live: 0, failed: 0 }
      end
    end

    setup do
      proxy = Object.new
      proxy.define_singleton_method(:container_sweep_orphaned_resources_activity) do
        TemporalWorkflowHelper::ActivityRef.new("container_sweep_orphaned_resources_activity", TASK_QUEUE)
      end
      ContainerSweepOrphanedResourcesWorkflow.stubs(:_preloaded_activities).returns(proxy)
    end

    test "executes the sweep activity and returns its summary" do
      result = run_workflow(ContainerSweepOrphanedResourcesWorkflow,
                            activities: [ FakeSweepActivity.new ], task_queue: TASK_QUEUE)

      assert_equal 4, result["reaped"]
      assert_equal 1, result["sessions"]
      assert_equal 2, result["kept_live"]
    end

    test "retries the activity under the max_attempts:2 policy (time-skips the backoff)" do
      FlakySweepActivity.attempts = 0

      result = run_workflow(ContainerSweepOrphanedResourcesWorkflow,
                            activities: [ FlakySweepActivity.new ], task_queue: TASK_QUEUE)

      assert_equal 2, FlakySweepActivity.attempts, "activity should be retried exactly once"
      assert_equal 0, result["reaped"]
    end
  end
end
