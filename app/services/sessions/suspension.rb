# frozen_string_literal: true

module Sessions
  # When an interactive session is suspended instead of finished, and what happens to it
  # afterwards. Design: docs/design/session-suspend-restore.md.
  #
  # A session is suspended at the end of its exec phase's signal wait (the 23-hour limit)
  # or when its owner presses Suspend. The cleanup activity decides which, takes the
  # checkpoint (Sessions::Checkpoint) and writes `suspended`; Restore starts a new session
  # from it (Sessions::Restore); the expiry sweep finishes it after RESTORE_WINDOW.
  module Suspension
    RESTORE_WINDOW = 30.days
    REMINDER_BEFORE = 3.days
    TIME_LIMIT = ContainerStrategies::AgentSessionStrategy::SIGNAL_TIMEOUT.seconds
    # How close to the limit a cleanup with nothing else asking for an end counts as the
    # limit. Every other way an interactive session ends carries an error or a finish.
    LIMIT_MARGIN = 30.minutes
    REQUESTED_KEY = "suspend_requested_at"
    ERROR_KEY = "suspend_error"
    EXPIRED_KEY = "suspend_expired"
    REMINDED_KEY = "suspend_reminded_at"

    module_function

    # Workflow steps are left out: their run waits on them with its own limit
    # (WorkflowExecutionWorkflow::INTERACTIVE_TIMEOUT), and a suspended step would have to
    # hold the run open. Without storage that signs uploads the archive has nowhere to go.
    def supported?(session)
      session.agent_session? && session.mode == "interactive" && session.user_id.present? && storage_signs_uploads?
    end

    def storage_signs_uploads?
      SessionCheckpointUploader.storages[:cache].respond_to?(:presign)
    end

    def requested?(session)
      session.metadata.to_h[REQUESTED_KEY].present?
    end

    def time_limit_reached?(session, now: Time.current)
      session.finishing_at.nil? && session.ready_at.present? && session.ready_at <= now - (TIME_LIMIT - LIMIT_MARGIN)
    end

    # Whether the cleanup that is starting ends the session by suspending it.
    def due?(session, error)
      return false if error.present? || session.cancelled? || session.failed?

      supported?(session) && (requested?(session) || time_limit_reached?(session))
    end

    def reason(session)
      requested?(session) ? "user" : "time_limit"
    end

    # When the live session will be suspended by the limit, for the warning shown before it.
    def suspends_at(session)
      return nil unless supported?(session) && session.ready_at && session.container_up?

      session.ready_at + TIME_LIMIT
    end

    def restorable?(session)
      session.suspended? && session.session_checkpoint.present? &&
        (session.restore_expires_at.nil? || session.restore_expires_at.future?)
    end

    # Called by the cleanup activity once the checkpoint is stored, in place of the
    # usual final state.
    def suspended!(session, now: Time.current)
      session.update!(state: "suspended", finished_at: session.finished_at || now, container_id: nil,
                      suspended_at: now, restore_expires_at: now + RESTORE_WINDOW)
      ActiveRecord.after_all_transactions_commit { SessionMailer.suspended(session.id).deliver_later }
    end

    # The session that continued it reached `ready`: the suspended one is done with.
    def restored!(restored)
      origin = restored.restored_from_session
      return unless origin&.suspended?

      origin.mark_restored!
    rescue StandardError => e
      Rails.logger.warn("[Suspension] could not mark session #{origin&.id} restored: #{e.message}")
    end
  end
end
