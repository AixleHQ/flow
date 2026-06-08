# frozen_string_literal: true

require "test_helper"

module Workflows
  class WorkflowExecutionWorkflowTest < ActiveSupport::TestCase
    setup do
      @workflow = WorkflowExecutionWorkflow.new
      @workflow.instance_variable_set(:@step_decisions, {})
      @workflow.instance_variable_set(:@step_run_to_step_id, {})
      @workflow.instance_variable_set(:@retry_overrides, {})
      @workflow.instance_variable_set(:@cancelled, false)

      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:error)
    end

    # --- auto_advance? ---

    test "auto_advance? returns true in non_interactive mode regardless of step flag" do
      @workflow.instance_variable_set(:@mode, "non_interactive")

      assert @workflow.send(:auto_advance?, {})
      assert @workflow.send(:auto_advance?, { "auto_run" => false })
    end

    test "auto_advance? returns true in mixed mode when auto_run is set with snake_case key" do
      @workflow.instance_variable_set(:@mode, "mixed")

      assert @workflow.send(:auto_advance?, { "auto_run" => true })
    end

    test "auto_advance? returns false in mixed mode when auto_run key is camelCase" do
      # This confirms the backend always reads snake_case; normalization must happen at ingestion.
      @workflow.instance_variable_set(:@mode, "mixed")

      refute @workflow.send(:auto_advance?, { "autoRun" => true })
    end

    test "auto_advance? returns false in interactive mode" do
      @workflow.instance_variable_set(:@mode, "interactive")

      refute @workflow.send(:auto_advance?, { "auto_run" => true })
    end

    # --- execute_steps_parallel signal race fix ---

    test "execute_steps_parallel initializes decision slot before launching session" do
      # Regression guard: @step_decisions[sr_id] must be nil-initialized BEFORE
      # launch_step_session is called. If the order is reversed, a container_finished
      # signal arriving during launch is silently overwritten and the workflow stalls.
      step_data = {
        "step_id" => 1,
        "step_run_id" => 42,
        "auto_run" => true,
        "depends_on_step_ids" => [],
        "on_failure" => "fail"
      }

      @workflow.stubs(:should_skip?).returns(false)
      @workflow.stubs(:prepare_step).returns(:ok)
      @workflow.stubs(:wait_for_all_parallel).returns({ 1 => :completed })

      slot_initialized_before_launch = false
      @workflow.stubs(:launch_step_session).with(42) do
        slot_initialized_before_launch = @workflow.instance_variable_get(:@step_decisions).key?(42)
        true
      end

      @workflow.send(:execute_steps_parallel, [ step_data ])

      assert slot_initialized_before_launch,
        "@step_decisions slot must exist before launch_step_session to avoid overwriting an early signal"
    end

    test "execute_steps_parallel preserves container_finished signal that arrives during launch" do
      # Simulates the race: the signal arrives while launch_step_session is executing.
      # With the fix in place, the slot is pre-initialized so the signal survives.
      step_data = {
        "step_id" => 1,
        "step_run_id" => 42,
        "auto_run" => true,
        "depends_on_step_ids" => [],
        "on_failure" => "fail"
      }

      @workflow.stubs(:should_skip?).returns(false)
      @workflow.stubs(:prepare_step).returns(:ok)

      @workflow.stubs(:launch_step_session).with(42) do
        # Simulate the signal arriving mid-launch
        @workflow.container_finished(42)
        true
      end

      results = {}
      @workflow.stubs(:wait_for_all_parallel).with do |pending, _res, _|
        sr_id = pending[1]
        results[:decision_at_wait] = @workflow.instance_variable_get(:@step_decisions)[sr_id]
        true
      end.returns({})

      @workflow.send(:execute_steps_parallel, [ step_data ])

      assert_equal :completed, results[:decision_at_wait],
        "container_finished signal must survive into wait_for_all_parallel"
    end
  end
end
