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
  # of waiting for ops that a revoked runner never answers (PROTOCOL.md §9).
  module Revocation
    module_function

    def end_sessions!(runner)
      held = RunnerEnvironment.where(runner_id: runner.id).holding_session.pluck(:current_session_id)
      signal_relay(runner)

      # A session that holds no machine and is not past its launch is waiting for
      # one, whatever its state says: `running` is set before a machine is taken.
      TerminalSession.where(runner_id: runner.id).not_ended.find_each do |session|
        end_session(runner, session, running: held.include?(session.id) || session.launched?)
      rescue StandardError => e
        # One session that cannot end must not keep the others waiting.
        Rails.logger.error("[Runners::Revocation] session #{session.id} of runner #{runner.id}: #{e.class}: #{e.message}")
        Sentry.capture_exception(e, extra: { runner_id: runner.id, session_id: session.id })
      end
    end

    def end_session(runner, session, running:)
      Machines.let_go!(session) if running
      # A compare-and-set: a session that finished or was cancelled meanwhile keeps its outcome.
      SessionService.fail_session_if(session: session, error_message: message(runner, session, running))
    end
    private_class_method :end_session

    # The relay closes the connection of every machine of the runner (4001).
    def signal_relay(runner)
      RunnerEnvironment.where(runner_id: runner.id).pluck(:id).each { |id| RelaySignals.machine_revoked(id) }
    end
    private_class_method :signal_relay

    def message(runner, session, running)
      return "Runner \"#{runner.name}\" was revoked, so the session running on it ended." if running

      pick_from = session.workflow_step? ? "on the workflow" : "for the session"
      Resolver.check_status!(runner, pick_from)
      "Runner \"#{runner.name}\" is revoked. Pick another runner #{pick_from}."
    rescue Resolver::Refused => e
      e.message
    end
    private_class_method :message
  end
end
