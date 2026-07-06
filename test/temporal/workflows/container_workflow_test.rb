# frozen_string_literal: true

require "test_helper"

module Workflows
  # Runs the real ContainerWorkflow end to end through the SDK time-skipping
  # WorkflowEnvironment (docs/testing.md §2 Temporal-workflow target). Every phase
  # (pull_image → create_container → start_container → exec → cleanup) dispatches to
  # the SAME `container_phase_activity`; a fake stand-in registered under that name
  # returns canned per-phase results, so we can assert the workflow's observable
  # outcome (return value + phase progression) without a real container runtime.
  class ContainerWorkflowTest < ActiveSupport::TestCase
    TASK_QUEUE = "container-workflow-test"

    # Records every phase it is asked to run (in dispatch order) and echoes the
    # phase + the state it received back out, so the test can prove the phase
    # ordering and the state hand-off between phases from the workflow's result.
    class EchoPhaseActivity < Temporalio::Activity::Definition
      activity_name "container_phase_activity"
      @phases = []
      class << self
        attr_accessor :phases
      end

      def execute(input)
        self.class.phases << input["phase"]
        { "phase" => input["phase"], "state_received" => input["state"] }
      end
    end

    # exec reports the agent already finished, so await_signal_if_needed must
    # short-circuit instead of blocking on the container_finished signal.
    class AgentCompletedActivity < Temporalio::Activity::Definition
      activity_name "container_phase_activity"
      def execute(input)
        if input["phase"] == "exec"
          { "agent_completed" => true, "phase" => "exec", "result" => "session done" }
        else
          { "phase" => input["phase"] }
        end
      end
    end

    setup do
      # The workflow resolves its activity from the class-level registry proxy;
      # point container_phase_activity at our test task queue.
      proxy = Object.new
      proxy.define_singleton_method(:container_phase_activity) do
        TemporalWorkflowHelper::ActivityRef.new("container_phase_activity", TASK_QUEUE)
      end
      ContainerWorkflow.stubs(:_preloaded_activities).returns(proxy)
    end

    test "runs every phase in order and returns the exec phase result" do
      EchoPhaseActivity.phases = []

      result = run_workflow(
        ContainerWorkflow,
        { session_id: 123, manifest: {} },
        activities: [ EchoPhaseActivity.new ], task_queue: TASK_QUEUE
      )

      # Flow: execute_phases (pull_image → create_container → start_container → exec)
      # then cleanup always runs.
      assert_equal %w[pull_image create_container start_container exec cleanup],
        EchoPhaseActivity.phases

      # run() returns @state, which is the exec phase's result — cleanup does not
      # overwrite it.
      assert_equal "exec", result["phase"]

      # Each phase receives the previous phase's result as its `state`, so the exec
      # result carries the start_container result forward: proves the hand-off.
      assert_equal "start_container", result.dig("state_received", "phase")
      assert_equal "create_container", result.dig("state_received", "state_received", "phase")
    end

    test "skips the await-signal wait when exec reports the agent already completed" do
      # Manifest asks exec to await container_finished; because the exec result flags
      # agent_completed, the workflow must finish without waiting for the signal.
      result = run_workflow(
        ContainerWorkflow,
        { session_id: 456, manifest: { exec: { await_signal: "container_finished" } } },
        activities: [ AgentCompletedActivity.new ], task_queue: TASK_QUEUE
      )

      assert result["agent_completed"]
      assert_equal "session done", result["result"]
      assert_equal "exec", result["phase"]
    end
  end
end
