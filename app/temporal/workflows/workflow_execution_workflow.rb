# frozen_string_literal: true

module Workflows
  class WorkflowExecutionWorkflow < Base
    INTERACTIVE_TIMEOUT = 82_800 # 23 hours

    workflow_signal
    def step_completed
      @step_decision = :completed
    end

    workflow_signal
    def step_skipped
      @step_decision = :skipped
    end

    workflow_signal
    def step_retried
      @step_decision = :retried
    end

    workflow_signal
    def workflow_cancelled
      @cancelled = true
    end

    def run(input)
      @step_decision = nil
      @cancelled = false
      workflow_run_id = input.workflow_run_id

      update_status(workflow_run_id, :running)

      steps = fetch_ordered_steps(workflow_run_id)
      mode = fetch_mode(workflow_run_id)

      steps.each do |step_data|
        break if @cancelled

        result = execute_step(workflow_run_id, step_data, mode)
        break if result == :failed || result == :cancelled
      end

      final_status = @cancelled ? :cancelled : :completed
      update_status(workflow_run_id, final_status)
    rescue StandardError => e
      Temporalio::Workflow.logger.error("[WorkflowExecutionWorkflow] Failed: #{e.message}")
      update_status(workflow_run_id, :failed)
      raise
    end

    private

    def fetch_ordered_steps(workflow_run_id)
      execute_activity(
        prepare_step_list_activity_ref,
        { workflow_run_id: workflow_run_id },
        start_to_close_timeout: 30
      )
    end

    def fetch_mode(workflow_run_id)
      result = execute_activity(
        fetch_mode_activity_ref,
        { workflow_run_id: workflow_run_id },
        start_to_close_timeout: 10
      )
      result["mode"]
    end

    def execute_step(workflow_run_id, step_data, mode)
      skip_result = check_skip_policy(workflow_run_id, step_data)
      return :skipped if skip_result && skip_result["should_skip"]

      step_run_id = step_data["step_run_id"] || create_step_run(workflow_run_id, step_data)

      execute_activity(
        prepare_step_activity_ref,
        { step_run_id: step_run_id },
        start_to_close_timeout: 300
      )

      if auto_advance?(step_data, mode)
        wait_for_container_completion(step_run_id)
        complete_step(step_run_id)
      else
        wait_for_interactive_decision(workflow_run_id, step_data, step_run_id, mode)
      end
    end

    def auto_advance?(step_data, mode)
      return true if mode == "non_interactive"
      return true if mode == "mixed" && step_data["allow_non_interactive"]

      false
    end

    def wait_for_container_completion(step_run_id)
      # Wait for a signal or timeout indicating the container finished
      @step_decision = nil
      Temporalio::Workflow.wait_condition(INTERACTIVE_TIMEOUT) { @step_decision || @cancelled }
    end

    def wait_for_interactive_decision(workflow_run_id, step_data, step_run_id, mode)
      @step_decision = nil
      Temporalio::Workflow.wait_condition(INTERACTIVE_TIMEOUT) { @step_decision || @cancelled }

      return :cancelled if @cancelled

      case @step_decision
      when :completed
        complete_step(step_run_id)
      when :skipped
        :skipped
      when :retried
        handle_retry(workflow_run_id, step_data, step_run_id, mode)
      else
        handle_failure(workflow_run_id, step_data, step_run_id, mode, 0)
      end
    end

    def complete_step(step_run_id)
      execute_activity(
        complete_step_activity_ref,
        { step_run_id: step_run_id },
        start_to_close_timeout: 300
      )
      :completed
    end

    def handle_retry(workflow_run_id, step_data, _step_run_id, mode)
      max_retries = step_data["max_retries"] || 0
      execute_step(workflow_run_id, step_data, mode)
    end

    def handle_failure(workflow_run_id, step_data, step_run_id, mode, retry_count)
      on_failure = step_data["on_failure"] || "fail"
      max_retries = step_data["max_retries"] || 0

      case on_failure
      when "retry"
        if retry_count < max_retries
          execute_step(workflow_run_id, step_data, mode)
        else
          :failed
        end
      when "skip"
        :skipped
      else
        :failed
      end
    end

    def check_skip_policy(workflow_run_id, step_data)
      execute_activity(
        check_skip_activity_ref,
        { workflow_run_id: workflow_run_id, step_id: step_data["step_id"] },
        start_to_close_timeout: 30
      )
    rescue StandardError
      nil
    end

    def create_step_run(workflow_run_id, step_data)
      result = execute_activity(
        create_step_run_activity_ref,
        { workflow_run_id: workflow_run_id, step_id: step_data["step_id"] },
        start_to_close_timeout: 30
      )
      result["step_run_id"]
    end

    def update_status(workflow_run_id, status)
      execute_activity(
        update_status_activity_ref,
        { workflow_run_id: workflow_run_id, status: status.to_s },
        start_to_close_timeout: 30
      )
    end

    def prepare_step_activity_ref
      WorkflowService.workflow_execution_workflow.activities.workflow_prepare_step_activity
    end

    def complete_step_activity_ref
      WorkflowService.workflow_execution_workflow.activities.workflow_complete_step_activity
    end

    def update_status_activity_ref
      WorkflowService.workflow_execution_workflow.activities.workflow_update_workflow_run_status_activity
    end

    def prepare_step_list_activity_ref
      WorkflowService.workflow_execution_workflow.activities.workflow_prepare_step_list_activity
    end

    def create_step_run_activity_ref
      WorkflowService.workflow_execution_workflow.activities.workflow_create_step_run_activity
    end

    def fetch_mode_activity_ref
      WorkflowService.workflow_execution_workflow.activities.workflow_fetch_mode_activity
    end

    def check_skip_activity_ref
      WorkflowService.workflow_execution_workflow.activities.workflow_check_skip_activity
    end
  end
end
