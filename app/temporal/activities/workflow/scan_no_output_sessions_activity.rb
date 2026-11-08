# frozen_string_literal: true

module Activities
  module Workflow
    # Terminates `ready` workflow-step sessions that have produced no terminal
    # output for Sessions::NoOutputWatchdog::NO_OUTPUT_THRESHOLD. This catches
    # sessions blocked on an interactive prompt (quota / spend-limit dialog)
    # that the quota-error scanner cannot detect because no error text appears.
    #
    # An interactive step is left alone, as the quota scanner leaves it: silence
    # is what one looks like while its person reviews the work, and whoever is
    # watching can answer a dialog in the web terminal themselves. So is a step
    # waiting for its agent's login to be renewed: Sessions::AuthPause bounds that
    # wait itself.
    #
    # Every candidate is read, however young: for a runtime judged by its screen
    # (Sessions::NoOutputWatchdog::SCREEN_RULE_RUNTIMES) the first read starts the
    # record of when the screen last changed, so a session whose screen froze early
    # is ended 30 minutes after that, not 30 minutes after a first read at minute 31.
    # The sweep runs every 5 minutes to keep those reads affordable, so a silent
    # session is ended 30 to 35 minutes after its screen (or, for other runtimes, its
    # log) stopped changing.
    class ScanNoOutputSessionsActivity < ::Activities::Base
      def run(_input = nil)
        terminated = 0
        skipped    = 0

        candidate_sessions.find_each do |session|
          # A runner session's ops are capped, so a machine that does not answer
          # cannot hold up the sweep.
          runtime = ContainerRuntime.for_session(session, op_timeout: Settings.runners.scan_op_timeout)
          watchdog = Sessions::NoOutputWatchdog.new(session, runtime: runtime)
          unless watchdog.stale?
            skipped += 1
            next
          end

          SessionService.fail_session(session: session, error_message: watchdog.message)
          terminated += 1
        rescue ContainerRuntime::ContainerUnreachableError => e
          log(:warn, "Skipping session #{session.id} (unreachable): #{e.message}")
          skipped += 1
        rescue StandardError => e
          log(:warn, "Failed to process session #{session.id}: #{e.message}")
        end

        { terminated:, skipped: }
      end

      private

      def candidate_sessions
        TerminalSession
          .where(state: "ready", session_type: :workflow_step)
          .where("mode IS NULL OR mode <> 'interactive'")
          .where.not(container_id: [ nil, "" ])
          .where.not(id: TerminalSession.auth_paused.select(:id))
      end
    end
  end
end
