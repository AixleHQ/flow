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

  # Nothing ever resolves here, so the wait is pure polling — which is exactly
  # the shape that used to spend a run's whole history budget.
  class BackoffProbe < WorkflowExecutionWorkflowV2
    def run(_input)
      @step_decisions = {}
      @cancelled = false
      @refreshes = 0
      started = Temporalio::Workflow.now
      wait_for_signal(1)
      { "refreshes" => @refreshes, "waited" => Temporalio::Workflow.now - started }
    end

    private

    def refresh_session_decisions(_ids)
      @refreshes += 1
      @step_decisions[1] = :completed if @refreshes >= 5
    end
  end

  class WorkflowExecutionWorkflowV2Test < ActiveSupport::TestCase
    test "queue waiting can exceed the legacy 23-hour parent timeout" do
      result = run_workflow(QueueWaitProbe, {}, activities: [], task_queue: "queue-wait-test")
      assert_equal "completed", result["decision"]
      assert_operator result["waited"], :>=, 90_000
    end

    test "an idle wait backs off instead of polling on a fixed interval forever" do
      result = run_workflow(BackoffProbe, {}, activities: [], task_queue: "backoff-test")

      assert_equal 5, result["refreshes"]
      # 30 + 60 + 120 + 240 seconds of timers between the five durable reads.
      assert_operator result["waited"], :>=, 450
    end

    test "early container completion signals cannot advance an admitted parent" do
      workflow = WorkflowExecutionWorkflowV2.new
      workflow.instance_variable_set(:@step_decisions, { 1 => nil })
      workflow.container_finished(1)
      assert_nil workflow.instance_variable_get(:@step_decisions)[1]
    end
  end
end
