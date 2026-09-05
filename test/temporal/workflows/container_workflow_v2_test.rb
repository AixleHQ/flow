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
