# frozen_string_literal: true

module Runners
  # What a runner's Revoke, and so its Delete, does to the sessions that name it
  # (docs/design/agent-runtimes/DESIGN.md §9.3): a session that runs on one of
  # its machines fails with the revoked message, and one that waits for a
  # machine ends with the message a launch gives for a revoked runner
  # (Resolver.check_status!). Nothing stays in `finishing` or waiting because
  # its runner was revoked.
  #
  #   Runners::Revocation.end_sessions!(runner)   # after the revoking transaction commits
  #
  # A machine that held one of those sessions stops holding it, so the session's
  # cleanup finds the machine absent and releases its admission at once, instead
  # of waiting for ops that a revoked runner never answers (PROTOCOL.md §8).
  module Revocation
    # A session that is not holding a machine and is not past its launch is
    # waiting for one, whatever its state says: `running` is set when the
    # launch starts, before a machine is taken.
    RUNNING_STATES = %w[ready finishing].freeze

    module_function

    def end_sessions!(runner)
      held = RunnerEnvironment.where(runner_id: runner.id).where.not(current_session_id: nil).pluck(:current_session_id)

      TerminalSession.where(runner_id: runner.id).where.not(state: TerminalSession::TERMINAL_STATES).find_each do |session|
        end_session(runner, session, running: held.include?(session.id) || session.state.in?(RUNNING_STATES))
      rescue StandardError => e
        Rails.logger.error("[Runners::Revocation] session #{session.id} of runner #{runner.id}: #{e.class}: #{e.message}")
      end
    end

    def end_session(runner, session, running:)
      if running
        RunnerEnvironment.where(runner_id: runner.id, current_session_id: session.id)
                         .update_all(current_session_id: nil, updated_at: Time.current)
      end
      SessionService.fail_session(session: session, error_message: message(runner, session, running))
    end
    private_class_method :end_session

    def message(runner, session, running)
      return "Runner \"#{runner.name}\" was revoked, so the session running on it ended." if running

      pick_from = session.session_type == "workflow_step" ? "on the workflow" : "for the session"
      Resolver.check_status!(runner, pick_from)
      "Runner \"#{runner.name}\" is revoked. Pick another runner #{pick_from}."
    rescue Resolver::Refused => e
      e.message
    end
    private_class_method :message
  end
end
