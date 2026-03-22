# frozen_string_literal: true

module Workflows
  class WorkflowExecutionWorkflow < Base
    INTERACTIVE_TIMEOUT = 82_800 # 23 hours

    workflow_signal
    def step_completed(step_run_id = nil)
      target = step_run_id || @current_interactive_step_run_id
      @step_decisions[target] = :completed if target
    end

    workflow_signal
    def step_skipped(step_run_id = nil)
      target = step_run_id || @current_interactive_step_run_id
      @step_decisions[target] = :skipped if target
    end

    workflow_signal
    def step_retried(payload = nil)
      if payload.is_a?(Hash)
        old_id = payload["old_step_run_id"]
        new_id = payload["new_step_run_id"]
        target = old_id || @current_interactive_step_run_id
        if target && new_id
          step_id = @step_run_to_step_id[target]
          @retry_overrides[step_id] = new_id if step_id
        end
      else
        target = payload || @current_interactive_step_run_id
      end
      @step_decisions[target] = :retried if target
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
      # Counts failed completions (complete_step / prepare_step / timeout) per step_id for on_failure retry caps
      @step_failure_counts = {}
      # step_run_id -> step_id reverse map, populated as step_runs are used
      @step_run_to_step_id = {}
      # step_id -> new_step_run_id, set when a user-initiated retry creates a new step_run
      @retry_overrides = {}
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

        results = execute_steps_parallel(ready)
        results.each do |step_id, result|
          if result == :failed || result == :cancelled
            @failed = true
            break
          end
          @completed_step_ids << step_id unless result == :retried
        end
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

      step_id = step_data["step_id"]
      step_run_id = @retry_overrides.delete(step_id) || step_data["step_run_id"] || create_step_run(step_data)
      @step_run_to_step_id[step_run_id] = step_id
      if prepare_step(step_run_id) == :failed
        return recover_from_step_failure(step_data, step_run_id)
      end

      launch_step_session(step_run_id)

      if auto_advance?(step_data)
        wait_for_signal(step_run_id)
        outcome = complete_step(step_run_id)
        return recover_from_step_completion_failure(step_data, step_run_id, outcome) if outcome == :failed

        outcome
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

        sr_id = @retry_overrides.delete(step_id) || step_data["step_run_id"] || create_step_run(step_data)
        @step_run_to_step_id[sr_id] = step_id
        if prepare_step(sr_id) == :failed
          results[step_id] = :failed
          next
        end

        step_run_ids[step_id] = sr_id
        launch_step_session(sr_id)
        @step_decisions[sr_id] = nil
      end

      steps_by_id = {}
      steps.each { |s| steps_by_id[s["step_id"]] = s }
      wait_for_all_parallel(step_run_ids, results, steps_by_id)
    end

    def wait_for_all_parallel(pending, results, steps_by_id)
      until pending.empty? || @cancelled
        Temporalio::Workflow.timeout(INTERACTIVE_TIMEOUT) do
          Temporalio::Workflow.wait_condition do
            @cancelled || pending.values.any? { |sr_id| @step_decisions[sr_id] }
          end
        end

        break if @cancelled

        pending.each do |step_id, sr_id|
          next unless @step_decisions[sr_id]
          decision = @step_decisions[sr_id]

          outcome = case decision
          when :skipped, :retried
                      decision
          else
                      result = complete_step(sr_id)
                      if result == :failed
                        sd = steps_by_id[step_id]
                        sd ? recover_from_step_completion_failure(sd, sr_id, result) : result
                      else
                        result
                      end
          end

          results[step_id] = outcome
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
      when :completed
        outcome = complete_step(step_run_id)
        return recover_from_step_completion_failure(step_data, step_run_id, outcome) if outcome == :failed

        outcome
      when :skipped then :skipped
      when :retried then execute_step(step_data)
      else                 resolve_step_failure(step_data)
      end
    end

    def resolve_step_failure(step_data)
      sid = step_data["step_id"]
      case step_data["on_failure"]
      when "retry"
        @step_failure_counts[sid] = (@step_failure_counts[sid] || 0) + 1
        max = step_data["max_retries"].to_i
        if max.positive? && @step_failure_counts[sid] <= max
          execute_step(step_data)
        else
          :failed
        end
      when "skip" then :skipped
      else :failed
      end
    end

    def recover_from_step_failure(step_data, step_run_id)
      recover_from_step_completion_failure(step_data, step_run_id, :failed)
    end

    def recover_from_step_completion_failure(step_data, step_run_id, failed_outcome)
      return failed_outcome if failed_outcome != :failed

      sid = step_data["step_id"]
      @step_failure_counts[sid] = (@step_failure_counts[sid] || 0) + 1

      case step_data["on_failure"].to_s
      when "retry"
        max = step_data["max_retries"].to_i
        if max.positive? && @step_failure_counts[sid] <= max
          new_sr_id = create_retry_step_run(step_data)
          @retry_overrides[sid] = new_sr_id
          execute_step(step_data)
        else
          :failed
        end
      when "skip"
        mark_step_skipped(step_run_id, "Skipped after failure (on_failure: skip)")
        :skipped
      else
        :failed
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

    def create_retry_step_run(step_data)
      result = execute_activity(activities.workflow_create_step_run_activity,
        { workflow_run_id: @workflow_run_id, step_id: step_data["step_id"], force_new: true },
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

    def mark_step_skipped(step_run_id, reason = nil)
      return unless step_run_id

      execute_activity(activities.workflow_mark_step_skipped_activity,
        { step_run_id: step_run_id, reason: reason },
        start_to_close_timeout: 30)
    rescue StandardError => e
      Temporalio::Workflow.logger.warn("[WorkflowExecution] Failed to mark step skipped: #{e.message}")
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
