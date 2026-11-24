# frozen_string_literal: true

module Sessions
  # The one owner of how a TerminalSession changes state: every move fires an event of
  # TerminalSessionStateMachine through here, and nothing else does (design:
  # docs/design/session-lifecycle.md).
  #
  # Two families, which must not be mixed:
  #
  # - **From outside the container workflow** (`enqueue`, `finish`, `suspend`, `fail`,
  #   `fail_if`, `cancel`, `reset_auth`). The workflow may still be running, so these also
  #   stop the admission's operations and signal or cancel the container's workflow, so
  #   that its cleanup runs.
  # - **From inside the container workflow, or after it is gone** (`start`, `ready`,
  #   `record_*`, `finalize`, `suspended`, `restored`, `expire_*`, `slot_released`). The
  #   state is recorded and nothing is signalled: the workflow is already ending.
  #
  # `SessionAdmissionService` moves sessions only through `transition!`, inside its writer
  # lock, where closing the admission and ending the session must be one write.
  module Lifecycle
    # The move `finalize` makes for each (from, to) pair. A session already in the state
    # it ends in, or already suspended or restored, makes no move: only its columns are written.
    FINALIZE_EVENTS = {
      %w[finishing finished] => :finish,
      %w[not_started finished] => :finish_without_request,
      %w[queued finished] => :finish_without_request,
      %w[running finished] => :finish_without_request,
      %w[ready finished] => :finish_without_request,
      %w[not_started failed] => :fail,
      %w[queued failed] => :fail,
      %w[running failed] => :fail,
      %w[ready failed] => :fail,
      %w[finishing failed] => :fail,
      %w[finished failed] => :fail_after_finish,
      %w[not_started cancelled] => :cancel,
      %w[queued cancelled] => :cancel,
      %w[running cancelled] => :cancel,
      %w[ready cancelled] => :cancel,
      %w[finishing cancelled] => :cancel
    }.freeze
    private_constant :FINALIZE_EVENTS

    # The events that end a session's part in its run: the run is woken once they commit.
    ENDING_EVENTS = %i[finish fail cancel expire_suspended_step finish_without_request].freeze
    private_constant :ENDING_EVENTS

    module_function

    # The primitive underneath every move: sets the error message, fires `event`, and runs
    # the effects of the move (design §3.6). Public for `SessionAdmissionService`, which
    # calls it inside its writer lock; it takes no lock of its own, so the caller holds
    # whatever it needs.
    #
    # The model's callbacks only assign. What leaves the process is sent here, after the
    # outermost transaction commits (at once when none is open), so a signal never reaches
    # a workflow before the state does and a rolled-back move announces nothing:
    #
    # - the parent run is woken by an ending event (ENDING_EVENTS), unless `notify: false`
    #   or the run's stop was requested; `finalize` passes `notify: false` (see there);
    # - the relay's `session_ended` goes out when the move leaves `ready`, for a runner session;
    # - `Suspension`'s `restored` runs when a session that continues a suspended one is `ready`.
    #
    # `save: false` fires the event without saving, for a caller that writes more columns
    # and saves once, inside its own transaction (`finalize`).
    def transition!(session, event, error_message: nil, notify: true, save: true)
      was_ready = session.ready?
      ActiveRecord::Base.transaction do
        session.update!(error_message: error_message) if error_message.present?
        session.public_send(save ? :"#{event}!" : event)
        start_run_execution(session) if event == :start
        schedule_effects(session, event, was_ready: was_ready, notify: notify)
      end
      session
    end

    # == From outside the container workflow ==

    def enqueue(session)
      SessionAdmissionService.enqueue!(session)
    end

    def finish(session)
      if session.queued?
        if session.step_run
          WorkflowService.cancel(run: session.step_run.workflow_run)
          return session.reload
        end
        return cancel(session)
      end
      unless session.may_start_finishing? || session.finishing?
        raise TerminalSession::InvalidStateError, "Cannot finish session in state: #{session.state}"
      end

      return unless session.may_start_finishing?

      stop_admission_operations(session)
      transition!(session, :start_finishing)

      if session.temporal_workflow_id.present?
        signal_container_finished(session)
      elsif session.may_finish?
        transition!(session, :finish)
      end
    end

    # Ends an interactive session the way the 23-hour limit does: its files and its
    # conversation are kept for Restore (Sessions::Suspension). The cleanup activity
    # reads the request off the session, so the signal is the same one Finish sends.
    def suspend(session)
      unless Sessions::Suspension.supported?(session) && session.container_up? && session.temporal_workflow_id.present?
        raise TerminalSession::InvalidStateError, "This session cannot be suspended"
      end

      stop_admission_operations(session)
      session.change_jsonb!(:metadata) { |doc| doc[Sessions::Suspension::REQUESTED_KEY] = Time.current.utc.iso8601 }
      transition!(session, :start_finishing)
      signal_container_finished(session)
      session
    end

    # Fail a session AND wake its container workflow, so the container's cleanup
    # phase actually runs. THE blessed way to fail a session from outside the
    # container workflow (watchdogs, scanners): do not hand-roll
    # `update!(error_message:) + fail!`.
    #
    # Why the signal is not optional: `TerminalSession#on_failed` only notifies the
    # PARENT workflow run ("workflow-execution-<id>", via WorkflowService), which
    # completes the step. The session's own container workflow is a different
    # execution ("agent-session-<id>") and it is parked in its `exec` phase
    # awaiting `container_finished` with a 23-hour signal timeout (see
    # WorkflowStepStrategy#phase_config). Failing the row without signalling that
    # execution leaves it spinning until the timeout, and its cleanup phase, the
    # only thing that deletes the pod, Service, IngressRoute and Middlewares,
    # never runs. Every such failure leaked its Kubernetes objects for a day.
    #
    # Ordering mirrors `finish`: transition first, signal second. The cleanup phase
    # decides the step's outcome from `session.state` (CompleteStepActivity), so it
    # must already read `failed`. Clearing `container_id` in `on_failed` is safe:
    # the cleanup phase takes its container reference from the workflow's own
    # accumulated state, not from the row.
    def fail(session, error_message: nil)
      session.update!(error_message: error_message) if error_message.present?
      return fail_admitted(session) if unreleased_admission?(session)

      stop_admission_operations(session)
      transition!(session, :fail) if session.may_fail?
      signal_container_finished(session) if session.temporal_workflow_id.present?
      session
    end

    # `fail` as a compare-and-set, for a caller that decided on a copy of the row
    # that may be stale (Sessions::Checks). The session is failed only if, under its row
    # lock, it is still in `expected_state` and the block (when given) still holds for the
    # locked row; the check and the transition are one transaction, so a finish_session or
    # an auth pause cannot land between them. The container workflow is woken after the
    # commit, as by `fail`.
    #
    # Without `expected_state`, the condition is "not finished, failed or cancelled yet", for
    # a caller that ends whatever the session is doing (a revoked runner or machine).
    #
    # @return [Boolean] whether the session was failed
    def fail_if(session, expected_state: nil, error_message: nil, &guard)
      still = lambda do |locked|
        in_state = expected_state.nil? ? !locked.ended? : locked.state == expected_state.to_s
        in_state && (guard.nil? || guard.call(locked))
      end

      if unreleased_admission?(session)
        return false unless SessionAdmissionService.fail_if!(session, error_message: error_message, &still)

        TemporalService.cancel_workflow(session.workflow_id) unless session.session_admission.reload.released_at
        WorkflowService.notify_container_finished(step_run: session.step_run) if session.step_run
        return true
      end

      failed = session.with_lock do
        next false unless still.call(session) && session.may_fail?

        transition!(session, :fail, error_message: error_message)
        true
      end
      return false unless failed

      stop_admission_operations(session)
      signal_container_finished(session) if session.temporal_workflow_id.present?
      true
    end

    # Cancels a session and the container workflow that runs it. `error_message` is the
    # reason a person is shown, kept next to a more specific one the session already has.
    #
    # A session with no admission has no workflow either, so its state is moved here:
    # nothing else will.
    def cancel(session, error_message: nil)
      if session.session_admission
        SessionAdmissionService.cancel!(session)
        TemporalService.cancel_workflow(session.workflow_id) unless session.session_admission.reload.released_at
      elsif session.may_cancel?
        transition!(session, :cancel)
      end
      if error_message.present?
        session.reload.update!(error_message: TerminalSession.preferred_error_message(session.error_message, error_message))
      end
      session
    end

    # The way out of a login that went wrong (a dead pane, a code pasted into the
    # shell) short of waiting out the login's TTL (AgentAuthStrategy.login_ttl). The
    # session is cancelled, so its container is torn down and nothing it captured is
    # saved (AgentAuthStrategy#before_cleanup); a session that already ended, or is
    # already being finished, is left as it is.
    def reset_auth(session)
      return session unless session.active?

      cancel(session)
    end

    # == From inside the container workflow, or after it is gone ==

    def start(session)
      transition!(session, :start) if session.may_start?
    end

    def ready(session, container_id:)
      session.container_id = container_id
      transition!(session, :mark_ready) if session.may_mark_ready?
    end

    def record_finishing(session)
      transition!(session, :start_finishing) if session.may_start_finishing?
    end

    # Idempotent: each move is guarded by its `may_*?` predicate, so a session that is
    # already finishing or finished only takes the moves it lacks.
    def record_finished(session)
      record_finishing(session)
      transition!(session, :finish) if session.may_finish?
    end

    def record_failure(session, error_message:)
      session.update(error_message: error_message)
      transition!(session, :fail) if session.may_fail?
    end

    # Records the final state of a session whose work is over, from what the runtime
    # reported, as soon as the work is over and independently of how long the runtime
    # takes to disappear. The parent workflow reads "unreleased + terminal" as `finishing`,
    # so it still waits for capacity to come back before starting the next step.
    #
    # The outcome rules are the model's (`TerminalSession#ending_state`, `#ending_error`).
    # The move is the event for the (from, to) pair, with no wake-up of the run: that
    # waits for `slot_released`, after the reservation is released. A session already in
    # the state it ends in, or one already suspended or restored (a repeated cleanup),
    # changes no state, only its columns: raising there would retry the cleanup forever,
    # before the reservation is released.
    #
    # `suspend` is the cleanup's decision to end the session suspended; it takes effect
    # when a checkpoint was kept and nothing failed.
    def finalize(session, error:, suspend: false)
      session.sync_usage
      ActiveRecord::Base.transaction do
        session.reload
        error = session.ending_error(error)
        # A checkpoint that could not be taken leaves no row, and the session ends as
        # any other does, its outputs already turned into assets by the strategy.
        if suspend && error.nil? && !session.cancelled? && session.session_checkpoint.present?
          suspended(session)
          next
        end

        to = session.ending_state(error)
        finished_at = session.finished_at
        session.error_message = TerminalSession.preferred_error_message(session.error_message, error)
        # Fired without saving: the one save below writes the state with its columns.
        # `notify: false` keeps the move from waking the run: `slot_released` does.
        unless session.state == to || session.suspended? || session.restored?
          transition!(session, finalize_event(session.state, to), notify: false, save: false)
        end
        session.finished_at = finished_at || Time.current
        session.container_id = nil
        session.save!
      end
    end

    # The session ends suspended: a checkpoint was stored in place of the usual final state.
    # Cleanup is repeated until the container is gone (a Kubernetes Pod outlives the first
    # pass), so it comes back here for a session already suspended.
    def suspended(session, now: Time.current)
      return if session.suspended? || session.restored?

      session.suspended_at = now
      session.restore_expires_at = Sessions::Suspension.window_end(session, now)
      transition!(session, :mark_suspended)
      session.step_run&.mark_suspended! if session.workflow_step?
      ActiveRecord.after_all_transactions_commit { SessionMailer.suspended(session.id).deliver_later }
    end

    # The session that continued a suspended one reached `ready`: the suspended one is
    # done with.
    def restored(restored_session)
      origin = restored_session.restored_from_session
      return unless origin&.suspended?

      transition!(origin, :mark_restored)
    rescue StandardError => e
      Rails.logger.warn("[Lifecycle] could not mark session #{origin&.id} restored: #{e.message}")
    end

    # The end of the restore window, or a suspended step its run no longer waits on.
    def expire_suspension(session)
      transition!(session, :expire_suspension)
    end

    # A suspended step whose window closed fails; the run, which reads the step's current
    # session, then fails the step and goes on as its on_failure says.
    def expire_suspended_step(session, error_message:, metadata:)
      ActiveRecord::Base.transaction do
        session.metadata = metadata
        transition!(session, :expire_suspended_step, error_message: error_message)
        session.step_run.update!(state: :running)
      end
    end

    # The reservation was released, so a run that waits for capacity can start its next
    # step. The signal only sets a decision flag, so a repeat changes nothing.
    def slot_released(session)
      notify_run(session)
    end

    # == Helpers ==

    def schedule_effects(session, event, was_ready:, notify:)
      if notify && ENDING_EVENTS.include?(event)
        ActiveRecord.after_all_transactions_commit { notify_run(session) }
      end
      if was_ready && session.on_runner?
        ActiveRecord.after_all_transactions_commit { Runners::RelaySignals.session_ended(session.id) }
      end
      if event == :mark_ready && session.restored_from_session_id
        ActiveRecord.after_all_transactions_commit { restored(session) }
      end
    end
    private_class_method :schedule_effects

    # A run starts the moment it is dispatched, while its first step may still sit in the
    # admission queue for minutes; its duration counts from here instead. Written in the
    # transition's transaction, so it rolls back with the state.
    def start_run_execution(session)
      return unless session.workflow_step?

      run_id = session.step_run&.workflow_run_id
      return unless run_id

      WorkflowRun.where(id: run_id, execution_started_at: nil).update_all(execution_started_at: session.started_at)
    end
    private_class_method :start_run_execution

    # Wakes the parent workflow run of a step session, unless the run is being stopped.
    def notify_run(session)
      return unless session.workflow_step?

      step_run = session.step_run
      return unless step_run&.workflow_run_id
      # A run being stopped was already told so (workflow_cancelled); its steps end with it.
      return if step_run.workflow_run.stop_requested?

      WorkflowService.notify_container_finished(step_run: step_run)
    rescue StandardError => e
      Rails.logger.error("[Sessions::Lifecycle] notify_run failed for session #{session.id}: #{e.message}")
    end
    private_class_method :notify_run

    def finalize_event(from, to)
      FINALIZE_EVENTS.fetch([ from, to ]) do
        raise TerminalSession::InvalidStateError, "Cannot end a session from #{from} to #{to}"
      end
    end
    private_class_method :finalize_event

    # The stop marker is what makes the admission service refuse the next phase of a
    # launch that is in flight.
    def stop_admission_operations(session)
      return unless session.session_admission

      SessionAdmissionService.transaction do
        admission = session.session_admission.reload
        admission.update!(stop_requested_at: admission.stop_requested_at || Time.current) unless admission.released_at
      end
    end
    private_class_method :stop_admission_operations

    def unreleased_admission?(session)
      admission = session.session_admission
      admission.present? && admission.released_at.nil?
    end
    private_class_method :unreleased_admission?

    # Marking the row failed frees nothing: the reservation is only released once
    # the runtime is confirmed gone (AD-6), and cancelling the session's container
    # workflow is what starts that. The verdict is `failed`, not `cancelled`: a
    # cancelled step session cancels its whole run (WorkflowExecutionWorkflowV2),
    # which would skip on_failure, quota classification and the Slack failure notice.
    def fail_admitted(session)
      SessionAdmissionService.cancel!(session, outcome: "failed")
      TemporalService.cancel_workflow(session.workflow_id) unless session.session_admission.reload.released_at
      # #cancel! fails the session under the writer lock, and `fail` wakes the parent
      # run only after that commits. This covers a session that had already ended,
      # which #cancel! leaves alone; the signal just sets a decision flag, so a
      # second one changes nothing.
      WorkflowService.notify_container_finished(step_run: session.step_run) if session.step_run
      session
    end
    private_class_method :fail_admitted

    def signal_container_finished(session)
      result = TemporalService.send_signal(session.workflow_id, :container_finished, session.step_run&.id)

      # A workflow that is already gone leaves the reservation to the reconciler,
      # which confirms the runtime is absent before releasing it.
      if result.is_a?(Hash) && !result[:ok]
        Rails.logger.warn("[Sessions::Lifecycle] Signal failed for session #{session.id}: #{result[:error]}")
      end
    rescue StandardError => e
      Rails.logger.error("[Sessions::Lifecycle] Failed to signal container_finished for session #{session.id}: #{e.message}")
    end
    private_class_method :signal_container_finished
  end
end
