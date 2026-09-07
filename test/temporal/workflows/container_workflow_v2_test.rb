# frozen_string_literal: true

require "test_helper"

module Workflows
  class ContainerWorkflowV2Test < ActiveSupport::TestCase
    TASK_QUEUE = "admitted-container-test"

    class CapacityPhaseActivity < Temporalio::Activity::Definition
      activity_name "container_admitted_phase_activity"
      attr_reader :phases

      def initialize
        @phases = []
      end

      def execute(input)
        @phases << input["phase"]
        if input["phase"] == "create_container" && @phases.count("create_container") == 1
          { "capacity_wait" => true }
        else
          { "phase" => input["phase"], "agent_completed" => true }
        end
      end
    end

    class PendingCleanupActivity < Temporalio::Activity::Definition
      activity_name "container_admitted_phase_activity"
      attr_reader :phases

      def initialize
        @phases = []
      end

      def execute(input)
        @phases << input["phase"]
        return { "cleanup_pending" => true } if input["phase"] == "cleanup" && @phases.count("cleanup") < 3

        { "phase" => input["phase"], "agent_completed" => true }
      end
    end

    def stub_activity_ref
      proxy = Object.new
      proxy.define_singleton_method(:container_admitted_phase_activity) do
        TemporalWorkflowHelper::ActivityRef.new("container_admitted_phase_activity", TASK_QUEUE)
      end
      ContainerWorkflowV2.stubs(:_preloaded_activities).returns(proxy)
    end

    test "an asynchronous delete is waited out, not reported as a failed session" do
      stub_activity_ref
      activity = PendingCleanupActivity.new

      result = run_workflow(ContainerWorkflowV2,
        { session_id: 123, admission_id: 456, permit_token: "permit", manifest: {} },
        activities: [ activity ], task_queue: TASK_QUEUE)

      assert_equal 3, activity.phases.count("cleanup"), "the workflow should retry until deletion is confirmed"
      assert_not_includes activity.phases, "on_failure", "a slow delete is not an execution failure"
      assert_equal "exec", result["phase"]
    end

    test "capacity wait retries provisioning without executing the agent twice" do
      proxy = Object.new
      proxy.define_singleton_method(:container_admitted_phase_activity) do
        TemporalWorkflowHelper::ActivityRef.new("container_admitted_phase_activity", TASK_QUEUE)
      end
      ContainerWorkflowV2.stubs(:_preloaded_activities).returns(proxy)
      activity = CapacityPhaseActivity.new
      result = run_workflow(ContainerWorkflowV2,
        { session_id: 123, admission_id: 456, permit_token: "permit", manifest: {} },
        activities: [ activity ], task_queue: TASK_QUEUE)
      assert_equal %w[pull_image create_container create_container start_container exec cleanup], activity.phases
      assert_equal "exec", result["phase"]
    end
  end
end
