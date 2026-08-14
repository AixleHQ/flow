# frozen_string_literal: true

module Activities
  module Workflow
    # Terminates `ready` workflow-step sessions that have produced no terminal
    # output for Sessions::NoOutputWatchdog::NO_OUTPUT_THRESHOLD. This catches
    # sessions blocked on an interactive prompt (quota / spend-limit dialog)
    # that the quota-error scanner cannot detect because no error text appears.
    class ScanNoOutputSessionsActivity < ::Activities::Base
      MIN_AGE = Sessions::NoOutputWatchdog::NO_OUTPUT_THRESHOLD + 1.minute

      def run(_input = nil)
        terminated = 0
        skipped    = 0

        candidate_sessions.find_each do |session|
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
          .where.not(container_id: [ nil, "" ])
          .where("COALESCE(started_at, created_at) < ?", MIN_AGE.ago)
      end

      def runtime
        @runtime ||= ContainerRuntime.build
      end
    end
  end
end
