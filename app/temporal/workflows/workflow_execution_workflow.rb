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
      target = step_run_id || @current_interactive_step_run_id
      @step_decisions[target] = :completed if target
    end

    workflow_signal
    def workflow_cancelled
      @cancelled = true
    end

    def run(input)
      init_state(input.workflow_run_id)
      update_status(:running)

      process_steps
      update_status(final_status)
    rescue Temporalio::Error::ActivityError => e
      Temporalio::Workflow.logger.error("[WorkflowExecution] Failed: #{extract_error_message(e)}")
      update_status(:failed)
      raise
    end

    private

    # --- Initialization ---

    def init_state(workflow_run_id)
      @workflow_run_id = workflow_run_id
      @step_decisions = {}
      @cancelled = false
      @failed = false
      @completed_step_ids = []
      @all_steps = fetch_ordered_steps
      @mode = fetch_mode
    end

    def final_status
      return :cancelled if @cancelled
      @failed ? :failed : :completed
    end

    # --- Main loop ---

    def process_steps
      until @failed || @cancelled
        ready = ready_steps
        break if ready.empty?

        auto_steps, interactive_steps = ready.partition { |s| auto_advance?(s) }

        process_auto_steps(auto_steps) if auto_steps.any?
        break if @failed || @cancelled

        process_interactive_steps(interactive_steps)
      end
    end

    def ready_steps
      @all_steps.select do |s|
        sid = s["step_id"]
        next false if @completed_step_ids.include?(sid)

        deps = s["depends_on_step_ids"] || []
        deps.all? { |dep_id| @completed_step_ids.include?(dep_id) }
      end
    end

    def auto_advance?(step_data)
      @mode == "non_interactive" || (@mode == "mixed" && step_data["auto_run"])
    end

    # --- Step processing ---

    def process_auto_steps(steps)
      results = execute_steps_parallel(steps)
      results.each do |step_id, result|
        if result == :failed || result == :cancelled
          @failed = true
          break
        end
        @completed_step_ids << step_id
      end
    end

    def process_interactive_steps(steps)
      steps.each do |step_data|
        break if @cancelled

        result = execute_step(step_data)
        if result == :failed || result == :cancelled
          @failed = true
          break
        end
        @completed_step_ids << step_data["step_id"]
      end
    end

    # --- Single step execution ---

    def execute_step(step_data)
      return :skipped if should_skip?(step_data)

      step_run_id = step_data["step_run_id"] || create_step_run(step_data)
      return :failed if prepare_step(step_run_id) == :failed

      launch_step_session(step_run_id)

      if auto_advance?(step_data)
        wait_for_signal(step_run_id)
        complete_step(step_run_id)
      else
        wait_for_interactive_decision(step_data, step_run_id)
      end
    end

    # --- Parallel execution ---

    def execute_steps_parallel(steps)
      results = {}
      step_run_ids = {}

      steps.each do |step_data|
        step_id = step_data["step_id"]
        if should_skip?(step_data)
          results[step_id] = :skipped
          next
        end

        sr_id = step_data["step_run_id"] || create_step_run(step_data)
        if prepare_step(sr_id) == :failed
          results[step_id] = :failed
          next
        end

        step_run_ids[step_id] = sr_id
        launch_step_session(sr_id)
        @step_decisions[sr_id] = nil
      end

      wait_for_all_parallel(step_run_ids, results)
    end

    def wait_for_all_parallel(pending, results)
      until pending.empty? || @cancelled
        Temporalio::Workflow.timeout(INTERACTIVE_TIMEOUT) do
          Temporalio::Workflow.wait_condition do
            @cancelled || pending.values.any? { |sr_id| @step_decisions[sr_id] }
          end
        end

        break if @cancelled

        pending.each do |step_id, sr_id|
          next unless @step_decisions[sr_id]
          results[step_id] = complete_step(sr_id)
        end

        pending.reject! { |step_id, _| results.key?(step_id) }
      end

      results
    end

    # --- Interactive flow ---

    def wait_for_interactive_decision(step_data, step_run_id)
      @current_interactive_step_run_id = step_run_id
      @step_decisions[step_run_id] = nil

      Temporalio::Workflow.timeout(INTERACTIVE_TIMEOUT) do
        Temporalio::Workflow.wait_condition { @step_decisions[step_run_id] || @cancelled }
      end

      @current_interactive_step_run_id = nil
      return :cancelled if @cancelled

      case @step_decisions[step_run_id]
      when :completed then complete_step(step_run_id)
      when :skipped   then :skipped
      when :retried   then execute_step(step_data)
      else                 resolve_step_failure(step_data)
      end
    end

    def resolve_step_failure(step_data)
      case step_data["on_failure"]
      when "retry"
        max = step_data["max_retries"] || 0
        max > 0 ? execute_step(step_data) : :failed
      when "skip" then :skipped
      else :failed
      end
    end

    # --- Activity calls ---

    def fetch_ordered_steps
      execute_activity(activities.workflow_prepare_step_list_activity,
        { workflow_run_id: @workflow_run_id }, start_to_close_timeout: 30)
    end

    def fetch_mode
      result = execute_activity(activities.workflow_fetch_mode_activity,
        { workflow_run_id: @workflow_run_id }, start_to_close_timeout: 10)
      result["mode"]
    end

    def create_step_run(step_data)
      result = execute_activity(activities.workflow_create_step_run_activity,
        { workflow_run_id: @workflow_run_id, step_id: step_data["step_id"] },
        start_to_close_timeout: 30)
      result["step_run_id"]
    end

    def prepare_step(step_run_id)
      result = execute_activity(activities.workflow_prepare_step_activity,
        { step_run_id: step_run_id }, start_to_close_timeout: 300)
      result["failed"] ? :failed : :ok
    end

    def launch_step_session(step_run_id)
      execute_activity(activities.workflow_launch_step_session_activity,
        { step_run_id: step_run_id }, start_to_close_timeout: 600)
    end

    def complete_step(step_run_id)
      result = execute_activity(activities.workflow_complete_step_activity,
        { step_run_id: step_run_id }, start_to_close_timeout: 300)
      result["failed"] ? :failed : :completed
    end

    def update_status(status)
      execute_activity(activities.workflow_update_workflow_run_status_activity,
        { workflow_run_id: @workflow_run_id, status: status.to_s },
        start_to_close_timeout: 30)
    end

    def should_skip?(step_data)
      result = execute_activity(activities.workflow_check_skip_activity,
        { workflow_run_id: @workflow_run_id, step_id: step_data["step_id"] },
        start_to_close_timeout: 30)
      result && result["should_skip"]
    rescue Temporalio::Error::ActivityError
      false
    end

    # --- Signal helpers ---

    def wait_for_signal(step_run_id)
      @step_decisions[step_run_id] = nil
      Temporalio::Workflow.timeout(INTERACTIVE_TIMEOUT) do
        Temporalio::Workflow.wait_condition { @step_decisions[step_run_id] || @cancelled }
      end
    end
  end
end
