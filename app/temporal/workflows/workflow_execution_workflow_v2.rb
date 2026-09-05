# frozen_string_literal: true

module Workflows
  # New histories poll durable session state. Queue time has no execution budget;
  # admitted children retain their own 24-hour execution timeout.
  class WorkflowExecutionWorkflowV2 < WorkflowExecutionWorkflow
    # Legacy strategy hooks can signal before runtime cleanup finishes. Durable
    # polling below is the completion authority for admitted sessions.
    workflow_signal
    def container_finished(step_run_id = nil)
    end

    private

    def wait_for_all_parallel(pending, results, steps_by_id)
      until pending.empty? || @cancelled
        refresh_session_decisions(pending.values)
        pending.each do |step_id, sr_id|
          decision = @step_decisions[sr_id]
          next unless decision
          outcome = if %i[skipped retried cancelled].include?(decision)
            decision
          else
            result = complete_step(sr_id)
            result == :failed ? recover_from_step_completion_failure(steps_by_id[step_id], sr_id, result) : result
          end
          results[step_id] = outcome
        end
        pending.reject! { |step_id, _| results.key?(step_id) }
        Temporalio::Workflow.sleep(30) unless pending.empty? || @cancelled
      end
      results
    end

    def wait_for_signal(step_run_id)
      until @step_decisions[step_run_id] || @cancelled
        refresh_session_decisions([ step_run_id ])
        Temporalio::Workflow.sleep(30) unless @step_decisions[step_run_id] || @cancelled
      end
    end

    def wait_for_interactive_decision(step_data, step_run_id)
      @current_interactive_step_run_id = step_run_id
      wait_for_signal(step_run_id)
      @current_interactive_step_run_id = nil
      return :cancelled if @cancelled
      case @step_decisions[step_run_id]
      when :completed
        outcome = complete_step(step_run_id)
        outcome == :failed ? recover_from_step_completion_failure(step_data, step_run_id, outcome) : outcome
      when :skipped then :skipped
      when :retried then execute_step(step_data)
      else :cancelled
      end
    end

    def refresh_session_decisions(ids)
      result = execute_activity(activities.workflow_step_session_status_activity,
        { workflow_run_id: @workflow_run_id, step_run_ids: ids }, start_to_close_timeout: 30)
      @cancelled ||= result["cancelled"]
      result["sessions"].each do |id, status|
        if status["state"] == "cancelled" || status["step_state"] == "cancelled"
          @cancelled = true
          @step_decisions[id.to_i] = :cancelled
        elsif %w[finished failed].include?(status["state"])
          @step_decisions[id.to_i] ||= :completed
        end
      end
    end
  end
end
