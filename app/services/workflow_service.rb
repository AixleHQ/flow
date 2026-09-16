# frozen_string_literal: true

class WorkflowService
  # A run was saved but its Temporal execution could not be started. Raised, not
  # returned: an undispatched run is an outage, not a validation error, and the
  # thing that used to happen instead — log a line and hand the caller a run that
  # looked started — is what let a queue stall go unnoticed for two hours.
  DispatchFailed = Class.new(StandardError)

  class << self
    def update(workflow:, params:)
      attrs = params.to_h
      if (incoming_config = attrs.delete("config")).present?
        workflow.merge_config!(incoming_config)
      end
      attrs.any? ? workflow.update(attrs) : workflow.errors.none?
    rescue ActiveRecord::RecordInvalid
      false
    end

    def start(workflow:, project:, user:, task: nil, mode: :interactive, overrides: {}, input_asset_ids: [], repository_ids: [], agent_runtime: nil, requested_model: nil, shared_context: {})
      run = project.workflow_runs.new(
        workflow: workflow,
        user: user,
        board_task_id: task&.id,
        mode: mode,
        step_overrides: overrides,
        input_asset_ids: input_asset_ids,
        repository_ids: repository_ids,
        agent_runtime: agent_runtime.presence,
        shared_context: { "requested_model" => requested_model.presence }.compact.merge(shared_context.to_h.stringify_keys)
      )

      validate_mode!(run, workflow, overrides)
      return run if run.errors.any?

      # Which launch path this run's history uses is decided once, here, and
      # then never re-read — that is what keeps a policy change from rewriting
      # the semantics of an already-running history. An unlocked read is enough:
      # SessionAdmissionPolicy.sync! refuses to flip the mode while any run is
      # pending, running or paused.
      run.shared_context = run.shared_context.merge("session_admission" => SessionAdmissionPolicy.enabled?)
      # Enrol the run in the outbox in the very write that creates it. From here
      # on a dispatch that never lands is a row the relay can find, instead of a
      # run indistinguishable from one the worker simply has not reached yet.
      run.relay_state = "pending"
      return run unless run.save

      workflow.steps.not_deleted.order(:position).each do |step|
        run.step_runs.find_or_create_by!(step: step)
      end

      dispatch!(run)
      record_activity(run, :workflow_started)
      broadcast_task_updated(run)

      run
    end

    # Turns a saved run into a Temporal execution, and is the only thing allowed
    # to call that done.
    #
    # Loud on purpose. This used to be a bare call whose return value was
    # discarded, under a `rescue StandardError` that logged one line and handed
    # back a run that read as started. TemporalService.start_workflow does not
    # raise on a failed RPC — it returns { ok: false, ... } — so a Temporal outage
    # never even reached that rescue: it produced a committed run nobody would
    # ever execute, and a success response. Now the caller gets an exception (and
    # Sentry an event), while the run stays enrolled in the outbox so
    # WorkflowRunRelay re-drives it within WorkflowRun::RELAY_GRACE.
    #
    # Safe to call again, which is what makes the relay safe: the execution id is
    # per-run and duplicates are rejected, with a rejected duplicate reported as
    # success — the execution this run needs already exists.
    def dispatch!(run)
      run.increment!(:relay_attempts)
      result = TemporalWorkflowRegistry.start_workflow_execution(run)

      if result.is_a?(Hash) && result[:ok]
        # update_columns, not update!: relay bookkeeping is not a change anyone
        # should be notified about, and update! would fire the run's broadcast on
        # every single start.
        run.update_columns(relay_state: "dispatched", relay_error: nil, updated_at: Time.current)
        return result
      end

      error = result.is_a?(Hash) ? result[:error] : "start_workflow_execution returned #{result.inspect}"
      run.update_columns(relay_error: error.to_s.first(255), updated_at: Time.current)

      # A deployment that has switched Temporal off has no executor to dispatch to
      # and no relay to recover with — the relay is itself a Temporal schedule.
      # Nothing is stranded, because nothing was ever going to run. Development and
      # test work this way; production does not, which is why the check is on the
      # deployment's own switch and not on the shape of the error.
      unless TemporalService.enabled?
        Rails.logger.info("[WorkflowService] Temporal is disabled; run ##{run.id} was not dispatched")
        return result
      end

      raise DispatchFailed, "WorkflowRun ##{run.id} was not dispatched to Temporal: #{error}"
    end

    def cancel(run:)
      SessionAdmissionService.transaction do
        run.lock!
        run.update!(stop_requested_at: run.stop_requested_at || Time.current)
      end
      send_signal(run, "workflow_cancelled")
      cancel_active_step_runs(run)
      run.cancel! if run.may_cancel?
      record_activity(run, :workflow_cancelled)
      broadcast_task_updated(run)
    end

    # Cancellation fan-out that crashed halfway leaves a run carrying a stop
    # marker over step runs that are still pending. Reconciliation replays just
    # the fan-out — the activity entry was already written by #cancel.
    def repair_cancellation(run)
      cancel_active_step_runs(run)
      broadcast_task_updated(run)
    end

    def complete(run:)
      run.complete! if run.may_complete?
      record_activity(run, :workflow_completed)
      broadcast_task_updated(run)
    end

    def fail(run:)
      run.fail! if run.may_fail?
      record_activity(run, :workflow_failed)
      broadcast_task_updated(run)
    end

    def approve_step(step_run:)
      step_run.mark_completed!
      send_signal(step_run.workflow_run, "step_completed", step_run.id)
    end

    # Retrying a step while its run's Temporal workflow execution is still open
    # (e.g. the "Retry" action on a waiting_input step) signals the live
    # execution. Once the execution has closed (the run itself is failed —
    # the common case, since the "Retry session" action only appears then),
    # signals go nowhere, so — same as the board card's "Retry" action
    # (TaskService.trigger_workflow) — a brand-new WorkflowRun is started
    # instead of trying to resume the closed one, reusing the original run's
    # parameters. The old failed run is left as-is; the new run runs every
    # step fresh.
    def retry_step(step_run:)
      run = step_run.workflow_run

      if TemporalService.workflow_open?(workflow_execution_id(run))
        retry_step_in_place(run, step_run)
      else
        retry_closed_run(run)
      end
    end

    def skip_step(step_run:, reason: nil)
      step_run.mark_skipped!(reason || "Skipped by user")
      send_signal(step_run.workflow_run, "step_skipped", step_run.id)
    end

    def notify_container_finished(step_run:)
      execution_id = workflow_execution_id(step_run.workflow_run)
      TemporalService.send_signal(execution_id, :container_finished, step_run.id)
    rescue StandardError => e
      Rails.logger.error("[WorkflowService] Failed to signal container_finished for step_run ##{step_run.id}: #{e.message}")
    end

    private

    def retry_step_in_place(run, step_run)
      new_step_run = run.step_runs.create!(step: step_run.step, state: :pending)
      result = send_signal(run, "step_retried",
                  { "old_step_run_id" => step_run.id, "new_step_run_id" => new_step_run.id })

      unless result[:ok]
        new_step_run.destroy
        return { ok: false, error: "Failed to retry: #{result[:error]}" }
      end

      { ok: true }
    end

    def retry_closed_run(run)
      return { ok: false, error: "This run can't be retried right now." } unless run.failed?

      new_run = start(
        workflow: run.workflow,
        project: run.project,
        user: run.user,
        task: run.board_task,
        mode: run.mode,
        overrides: run.step_overrides,
        input_asset_ids: run.input_asset_ids,
        repository_ids: run.repository_ids,
        agent_runtime: run.agent_runtime,
        shared_context: run.shared_context
      )

      unless new_run.persisted?
        return { ok: false, error: new_run.errors.full_messages.to_sentence.presence || "Could not start a new run." }
      end

      { ok: true, run: new_run }
    end

    def workflow_execution_id(run)
      "workflow-execution-#{run.id}"
    end

    def send_signal(run, signal_name, payload = nil)
      TemporalService.send_signal(workflow_execution_id(run), signal_name, payload)
    rescue StandardError => e
      Rails.logger.error("[WorkflowService] Failed to send signal #{signal_name} for run ##{run.id}: #{e.message}")
      { ok: false, error: e.message }
    end

    def validate_mode!(run, workflow, overrides)
      return unless run.non_interactive?

      blocking_steps = workflow.steps.not_deleted.reject do |step|
        override = overrides[step.id.to_s]
        override ? override["auto_run"] : step.allow_non_interactive
      end

      return if blocking_steps.empty?

      names = blocking_steps.map(&:name)
      run.errors.add(:mode, "Cannot run fully automatic: steps #{names.join(', ')} require user interaction")
    end

    def cancel_active_step_runs(run)
      run.step_runs.where(state: %w[pending running waiting_input]).find_each do |sr|
        session = sr.terminal_session
        SessionService.cancel(session: session) if session
        # Read after the cancel: the session is where a diagnosed reason lives, and
        # cleanup may have just written one.
        sr.mark_cancelled!(diagnosed_reason(session))
      rescue StandardError => e
        Rails.logger.warn("[WorkflowService] Failed to cancel step_run ##{sr.id}: #{e.message}")
      end
    end

    # Only a reason worth showing: the generic cancellation text says nothing the
    # step's own `cancelled` state does not already say.
    def diagnosed_reason(session)
      return nil unless session

      message = session.reload.error_message
      return nil if message.blank? || TerminalSession::GENERIC_ERROR_MESSAGES.include?(message)

      message
    rescue StandardError => e
      Rails.logger.warn("[WorkflowService] Failed to read cancellation reason: #{e.message}")
      nil
    end

    def broadcast_task_updated(run)
      return unless run.board_task_id.present?

      run.board_task.board.touch
    rescue StandardError => e
      Rails.logger.warn("[WorkflowService] Failed to broadcast task update for run ##{run.id}: #{e.message}")
    end

    def record_activity(run, event_type)
      return unless run.board_task_id.present?

      board = run.board_task.board
      BoardActivity.create!(
        board: board, board_task: run.board_task, event_type: event_type,
        actor: run.user, actor_type: :system,
        metadata: { workflow_name: run.workflow.name, workflow_run_id: run.id }
      )
      board.touch
    rescue StandardError => e
      Rails.logger.warn("[WorkflowService] Failed to record #{event_type} activity for run ##{run.id}: #{e.message}")
    end
  end
end
