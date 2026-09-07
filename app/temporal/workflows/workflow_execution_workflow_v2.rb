# frozen_string_literal: true

module Workflows
  # Parent workflow for runs whose step sessions go through the admission queue.
  #
  # A queued step has no container and no signal source yet, so the parent can no
  # longer treat "the container told me it finished" as the completion event.
  # Instead the database is the authority and signals are demoted to wake-ups:
  # they cut the latency of the next durable read to zero without letting a
  # session that has not yet returned its capacity advance the run.
  #
  # Polling backs off because history is finite. A step that is genuinely waiting
  # on a human for a week must not spend the run's 51,200-event budget on
  # thirty-second heartbeats — and it does not have to, because every event that
  # actually changes a session's state also signals.
  class WorkflowExecutionWorkflowV2 < WorkflowExecutionWorkflow
    INITIAL_POLL_INTERVAL = 30
    MAX_POLL_INTERVAL = 900

    # Container-lifecycle signals arrive before runtime cleanup finishes, so they
    # are a wake-up, not a verdict.
    workflow_signal
    def container_finished(_step_run_id = nil)
      @session_wake = true
    end

    private

    def wait_for_all_parallel(pending, results, steps_by_id)
      until pending.empty? || @cancelled
        await_session_change(pending.values) do
          @cancelled || pending.values.any? { |sr_id| @step_decisions[sr_id] }
        end
        break if @cancelled

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
      end
      results
    end

    def wait_for_signal(step_run_id)
      await_session_change([ step_run_id ]) { @step_decisions[step_run_id] || @cancelled }
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

    # Read durable state, then sleep until something signals or the backoff
    # window expires — whichever comes first. A signal resets the backoff, so an
    # active run stays responsive while an idle one goes quiet.
    def await_session_change(ids, &ready)
      interval = INITIAL_POLL_INTERVAL
      loop do
        @session_wake = false
        refresh_session_decisions(ids)
        return if ready.call

        begin
          Temporalio::Workflow.timeout(interval) do
            Temporalio::Workflow.wait_condition { ready.call || @session_wake }
          end
          interval = INITIAL_POLL_INTERVAL
        rescue Timeout::Error
          interval = [ interval * 2, MAX_POLL_INTERVAL ].min
        end
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
