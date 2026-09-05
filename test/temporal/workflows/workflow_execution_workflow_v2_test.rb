# frozen_string_literal: true

require "test_helper"

module Workflows
  class QueueWaitProbe < WorkflowExecutionWorkflowV2
    def run(_input)
      @step_decisions = {}
      @cancelled = false
      started = Temporalio::Workflow.now
      wait_for_signal(1)
      { "decision" => @step_decisions[1].to_s, "waited" => Temporalio::Workflow.now - started }
    end

    private

    # A deterministic stand-in for a slow queue; the production wait loop and
    # SDK timers are real. Time-skipping makes this a fast 25-hour regression.
    def refresh_session_decisions(_ids)
      Temporalio::Workflow.sleep(90_000)
      @step_decisions[1] = :completed
    end
  end

  class WorkflowExecutionWorkflowV2Test < ActiveSupport::TestCase
    test "queue waiting can exceed the legacy 23-hour parent timeout" do
      result = run_workflow(QueueWaitProbe, {}, activities: [], task_queue: "queue-wait-test")
      assert_equal "completed", result["decision"]
      assert_operator result["waited"], :>=, 90_000
    end

    test "early container completion signals cannot advance an admitted parent" do
      workflow = WorkflowExecutionWorkflowV2.new
      workflow.instance_variable_set(:@step_decisions, { 1 => nil })
      workflow.container_finished(1)
      assert_nil workflow.instance_variable_get(:@step_decisions)[1]
    end
  end
end
