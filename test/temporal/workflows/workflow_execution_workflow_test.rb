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

    # --- End-to-end run via the SDK time-skipping WorkflowEnvironment ---
    #
    # These exercise the real #run orchestration (init_state -> update_status(:running)
    # -> process_steps -> final_status -> update_status(:completed)) through the SDK
    # with fake activities registered on the worker under the real activity names
    # (docs/testing.md §2 Temporal-workflow target). They cover the signal-free happy
    # paths: an empty workflow and skipped steps, where process_steps completes without
    # waiting on any container_finished / step_* signal. The activity dispatch, the
    # ready_steps dependency gating and the multi-iteration loop all run for real.

    E2E_TASK_QUEUE = "workflow-execution-test"

    # Resolves any activities.workflow_*_activity accessor to a ref pointing at the
    # test task queue, standing in for the class-level TemporalWorkflowRegistry proxy.
    class ActivitiesProxy
      def initialize(task_queue)
        @task_queue = task_queue
      end

      def method_missing(name, *)
        TemporalWorkflowHelper::ActivityRef.new(name.to_s, @task_queue)
      end

      def respond_to_missing?(*)
        true
      end
    end

    class FakePrepareStepListActivity < Temporalio::Activity::Definition
      activity_name "workflow_prepare_step_list_activity"
      class << self
        attr_accessor :steps
      end

      def execute(_input = nil)
        self.class.steps || []
      end
    end

    class FakeFetchModeActivity < Temporalio::Activity::Definition
      activity_name "workflow_fetch_mode_activity"
      class << self
        attr_accessor :mode
      end

      def execute(_input = nil)
        { "mode" => (self.class.mode || "non_interactive") }
      end
    end

    class FakeCheckSkipActivity < Temporalio::Activity::Definition
      activity_name "workflow_check_skip_activity"
      class << self
        attr_accessor :should_skip
      end

      def execute(_input = nil)
        { "should_skip" => self.class.should_skip }
      end
    end

    # Records every status the workflow drives the run through and echoes it back, so
    # #run's return value (the final update_status result) is observable.
    class RecordingUpdateStatusActivity < Temporalio::Activity::Definition
      activity_name "workflow_update_workflow_run_status_activity"
      class << self
        attr_accessor :statuses
      end

      def execute(input = nil)
        status = input.is_a?(Hash) ? (input["status"] || input[:status]) : nil
        (self.class.statuses ||= []) << status
        { "status" => status }
      end
    end

    # Safety-net fakes for the step-execution activities. The signal-free paths below
    # never reach these, but registering them keeps the worker robust to dispatch.
    class FakeCreateStepRunActivity < Temporalio::Activity::Definition
      activity_name "workflow_create_step_run_activity"
      def execute(_input = nil)
        { "step_run_id" => 999 }
      end
    end

    class FakePrepareStepActivity < Temporalio::Activity::Definition
      activity_name "workflow_prepare_step_activity"
      def execute(_input = nil)
        { "failed" => false }
      end
    end

    class FakeLaunchStepSessionActivity < Temporalio::Activity::Definition
      activity_name "workflow_launch_step_session_activity"
      def execute(_input = nil)
        {}
      end
    end

    class FakeCompleteStepActivity < Temporalio::Activity::Definition
      activity_name "workflow_complete_step_activity"
      def execute(_input = nil)
        { "failed" => false }
      end
    end

    class FakeMarkStepSkippedActivity < Temporalio::Activity::Definition
      activity_name "workflow_mark_step_skipped_activity"
      def execute(_input = nil)
        {}
      end
    end

    def e2e_activities
      [
        FakePrepareStepListActivity.new,
        FakeFetchModeActivity.new,
        FakeCheckSkipActivity.new,
        RecordingUpdateStatusActivity.new,
        FakeCreateStepRunActivity.new,
        FakePrepareStepActivity.new,
        FakeLaunchStepSessionActivity.new,
        FakeCompleteStepActivity.new,
        FakeMarkStepSkippedActivity.new
      ]
    end

    def stub_activities_proxy!
      WorkflowExecutionWorkflow.stubs(:_preloaded_activities)
                               .returns(ActivitiesProxy.new(E2E_TASK_QUEUE))
    end

    test "run drives an empty workflow (no steps) to completed end-to-end" do
      RecordingUpdateStatusActivity.statuses = []
      FakePrepareStepListActivity.steps = []
      FakeFetchModeActivity.mode = "non_interactive"
      FakeCheckSkipActivity.should_skip = false
      stub_activities_proxy!

      result = run_workflow(
        WorkflowExecutionWorkflow, { workflow_run_id: 123 },
        activities: e2e_activities, task_queue: E2E_TASK_QUEUE
      )

      assert_equal "completed", result["status"], "run should report the terminal status"
      assert_equal %w[running completed], RecordingUpdateStatusActivity.statuses,
        "run must move the workflow_run through running then completed"
    end

    test "run completes a non_interactive workflow whose only step is skipped" do
      RecordingUpdateStatusActivity.statuses = []
      FakePrepareStepListActivity.steps = [
        { "step_id" => 1, "depends_on_step_ids" => [], "on_failure" => "fail" }
      ]
      FakeFetchModeActivity.mode = "non_interactive"
      FakeCheckSkipActivity.should_skip = true
      stub_activities_proxy!

      result = run_workflow(
        WorkflowExecutionWorkflow, { workflow_run_id: 123 },
        activities: e2e_activities, task_queue: E2E_TASK_QUEUE
      )

      assert_equal "completed", result["status"]
      assert_equal "completed", RecordingUpdateStatusActivity.statuses.last
    end

    test "run honors step dependencies across loop iterations when all steps skip" do
      # step 2 depends on step 1: it must only become ready after step 1 completes,
      # forcing a second process_steps iteration. Both skip, so no signals are needed.
      RecordingUpdateStatusActivity.statuses = []
      FakePrepareStepListActivity.steps = [
        { "step_id" => 1, "depends_on_step_ids" => [], "on_failure" => "fail" },
        { "step_id" => 2, "depends_on_step_ids" => [ 1 ], "on_failure" => "fail" }
      ]
      FakeFetchModeActivity.mode = "non_interactive"
      FakeCheckSkipActivity.should_skip = true
      stub_activities_proxy!

      result = run_workflow(
        WorkflowExecutionWorkflow, { workflow_run_id: 123 },
        activities: e2e_activities, task_queue: E2E_TASK_QUEUE
      )

      assert_equal "completed", result["status"]
    end
  end
end
