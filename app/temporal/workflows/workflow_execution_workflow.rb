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

    # A signal handler can run before `run` does — in the first activation, for a
    # signal delivered while no worker was polling — so what the handlers write
    # exists from construction, and `run` keeps it.
    def initialize
      super
      reset_signal_state
    end

    def run(input)
      init_state(input.workflow_run_id)
      update_status(:running)

      process_steps
      update_status(final_status, reason: @failure_reason)
    rescue Temporalio::Error::ActivityError => e
      Temporalio::Workflow.logger.error("[WorkflowExecution] Failed: #{extract_error_message(e)}")
      update_status(:failed)
      raise
    end

    private

    # --- Initialization ---

    def init_state(workflow_run_id)
      # Code without this patch threw away what arrived before `run`, and its
      # histories must replay that way. Retirement: docs/architecture/temporal-versioning.md.
      reset_signal_state unless Temporalio::Workflow.patched("keep-signals-delivered-before-run")
      @workflow_run_id = workflow_run_id
      @failed = false
      @completed_step_ids = []
      @all_steps = fetch_ordered_steps
      @mode = fetch_mode
      # Counts failed completions (complete_step / prepare_step / timeout) per step_id for on_failure retry caps
      @step_failure_counts = {}
      # step_run_ids where CompleteStepActivity detected a quota error — must never be retried
      @quota_error_step_run_ids = {}
    end

    def reset_signal_state
      @step_decisions = {}
      @cancelled = false
      # step_run_id -> step_id, populated as step_runs are used
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
        if ready.empty?
          unsatisfiable_dependencies!
          break
        end

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

    # Nothing is ready, yet steps are left: they wait on each other, or on a step
    # that is not in the run. They will never start, so the run has not completed.
    def unsatisfiable_dependencies!
      waiting = @all_steps.map { |s| s["step_id"] } - @completed_step_ids
      return if waiting.empty?

      @failed = true
      @failure_reason = "unsatisfiable_dependencies"
      Temporalio::Workflow.logger.error("[WorkflowExecution] Steps #{waiting.join(', ')} can never start: unsatisfiable dependencies")
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

    # --- Single step execution ---

    def execute_step(step_data)
      return :skipped if should_skip?(step_data)

      step_id = step_data["step_id"]
      step_run_id = @retry_overrides.delete(step_id) || step_data["step_run_id"] || create_step_run(step_data)
      @step_run_to_step_id[step_run_id] = step_id
      if prepare_step(step_run_id) == :failed
        return recover_from_step_failure(step_data, step_run_id)
      end

      # Cleared before the launch, not after it: a session can finish, or be
      # approved, while its launch activity is still returning.
      @step_decisions[step_run_id] = nil if keep_signals_delivered_during_launch?
      begin
        launch_step_session(step_run_id)
      rescue Temporalio::Error::ActivityError
        return recover_from_step_failure(step_data, step_run_id)
      end

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
        # Initialize the decision slot before launching so any container_finished
        # signal that arrives during launch is not overwritten by a subsequent nil-init.
        @step_decisions[sr_id] = nil
        begin
          launch_step_session(sr_id)
        rescue Temporalio::Error::ActivityError
          results[step_id] = :failed
          step_run_ids.delete(step_id)
          next
        end
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
      @step_decisions[step_run_id] = nil unless keep_signals_delivered_during_launch?

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
      return :failed if @quota_error_step_run_ids[step_run_id]

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
      @quota_error_step_run_ids[step_run_id] = true if result["quota_error"]
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

    def update_status(status, reason: nil)
      execute_activity(activities.workflow_update_workflow_run_status_activity,
        { workflow_run_id: @workflow_run_id, status: status.to_s, reason: reason }.compact,
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
      @step_decisions[step_run_id] = nil unless keep_signals_delivered_during_launch?
      Temporalio::Workflow.timeout(INTERACTIVE_TIMEOUT) do
        Temporalio::Workflow.wait_condition { @step_decisions[step_run_id] || @cancelled }
      end
    end

    # Code without this patch cleared the decision after the launch, and its
    # histories must replay that way.
    def keep_signals_delivered_during_launch?
      Temporalio::Workflow.patched("keep-signals-delivered-during-launch")
    end
  end
end
