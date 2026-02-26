# frozen_string_literal: true

module Workflows
  class WorkflowExecutionWorkflow < Base
    INTERACTIVE_TIMEOUT = 82_800 # 23 hours

    workflow_signal
    def step_completed
      @step_decisions[@current_interactive_step_run_id] = :completed if @current_interactive_step_run_id
    end

    workflow_signal
    def step_skipped
      @step_decisions[@current_interactive_step_run_id] = :skipped if @current_interactive_step_run_id
    end

    workflow_signal
    def step_retried
      @step_decisions[@current_interactive_step_run_id] = :retried if @current_interactive_step_run_id
    end

    workflow_signal
    def container_finished(step_run_id = nil)
      if step_run_id
        @step_decisions[step_run_id] = :completed
      elsif @current_interactive_step_run_id
        @step_decisions[@current_interactive_step_run_id] = :completed
      end
    end

    workflow_signal
    def workflow_cancelled
      @cancelled = true
    end

    def run(input)
      @step_decisions = {}
      @cancelled = false
      workflow_run_id = input.workflow_run_id

      update_status(workflow_run_id, :running)

      all_steps = fetch_ordered_steps(workflow_run_id)
      mode = fetch_mode(workflow_run_id)

      completed_step_ids = []
      failed = false

      until failed || @cancelled
        ready = all_steps.select do |s|
          sid = s["step_id"]
          next false if completed_step_ids.include?(sid)

          deps = s["depends_on_step_ids"] || []
          deps.all? { |dep_id| completed_step_ids.include?(dep_id) }
        end

        break if ready.empty?

        auto_steps, interactive_steps = ready.partition { |s| auto_advance?(s, mode) }

        if auto_steps.any?
          results = execute_steps_parallel(workflow_run_id, auto_steps, mode)
          results.each do |step_id, result|
            if result == :failed || result == :cancelled
              failed = true
              break
            end
            completed_step_ids << step_id
          end
          next unless failed
        end

        break if failed || @cancelled

        interactive_steps.each do |step_data|
          break if @cancelled

          result = execute_step(workflow_run_id, step_data, mode)
          if result == :failed || result == :cancelled
            failed = true
            break
          end
          completed_step_ids << step_data["step_id"]
        end
      end

      final_status = @cancelled ? :cancelled : (failed ? :failed : :completed)
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

      prepare_result = execute_activity(
        prepare_step_activity_ref,
        { step_run_id: step_run_id },
        start_to_close_timeout: 300
      )

      return :failed if prepare_result["failed"]

      launch_step_session(step_run_id)

      if auto_advance?(step_data, mode)
        wait_for_container_completion(step_run_id)
        complete_step(step_run_id)
      else
        wait_for_interactive_decision(workflow_run_id, step_data, step_run_id, mode)
      end
    end

    def auto_advance?(step_data, mode)
      return true if mode == "non_interactive"
      return true if mode == "mixed" && step_data["auto_run"]

      false
    end

    def execute_steps_parallel(workflow_run_id, steps_data, mode)
      results = {}
      step_run_ids = {}

      steps_data.each do |step_data|
        step_id = step_data["step_id"]
        skip_result = check_skip_policy(workflow_run_id, step_data)
        if skip_result && skip_result["should_skip"]
          results[step_id] = :skipped
          next
        end

        sr_id = step_data["step_run_id"] || create_step_run(workflow_run_id, step_data)

        prepare_result = execute_activity(
          prepare_step_activity_ref,
          { step_run_id: sr_id },
          start_to_close_timeout: 300
        )

        if prepare_result["failed"]
          results[step_id] = :failed
          next
        end

        step_run_ids[step_id] = sr_id
        launch_step_session(sr_id)
        @step_decisions[sr_id] = nil
      end

      pending_ids = step_run_ids.dup
      until pending_ids.empty? || @cancelled
        Temporalio::Workflow.timeout(INTERACTIVE_TIMEOUT) do
          Temporalio::Workflow.wait_condition do
            @cancelled || pending_ids.values.any? { |sr_id| @step_decisions[sr_id] }
          end
        end

        break if @cancelled

        pending_ids.each do |step_id, sr_id|
          next unless @step_decisions[sr_id]

          results[step_id] = complete_step(sr_id)
        end

        pending_ids.reject! { |step_id, _| results.key?(step_id) }
      end

      results
    end

    def wait_for_container_completion(step_run_id)
      @step_decisions[step_run_id] = nil
      Temporalio::Workflow.timeout(INTERACTIVE_TIMEOUT) do
        Temporalio::Workflow.wait_condition { @step_decisions[step_run_id] || @cancelled }
      end
    end

    def wait_for_interactive_decision(workflow_run_id, step_data, step_run_id, mode)
      @current_interactive_step_run_id = step_run_id
      @step_decisions[step_run_id] = nil

      Temporalio::Workflow.timeout(INTERACTIVE_TIMEOUT) do
        Temporalio::Workflow.wait_condition { @step_decisions[step_run_id] || @cancelled }
      end

      @current_interactive_step_run_id = nil
      return :cancelled if @cancelled

      case @step_decisions[step_run_id]
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
      result = execute_activity(
        complete_step_activity_ref,
        { step_run_id: step_run_id },
        start_to_close_timeout: 300
      )
      result["failed"] ? :failed : :completed
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

    def launch_step_session(step_run_id)
      execute_activity(
        launch_step_session_activity_ref,
        { step_run_id: step_run_id },
        start_to_close_timeout: 600
      )
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

    def launch_step_session_activity_ref
      WorkflowService.workflow_execution_workflow.activities.workflow_launch_step_session_activity
    end
  end
end
