# frozen_string_literal: true

# ScanQuotaErrorsActivity
# Finds active workflow_step sessions and checks for quota error patterns in
# error_message and live terminal output. When detected, transitions the session
# to "failed" which triggers container_finished → CompleteStepActivity.
module Activities
  module Workflow
    class ScanQuotaErrorsActivity < ::Activities::Base
      ACTIVE_STATES = %w[running ready].freeze
      # Avoid scanning sessions that just started (container/tmux not ready yet)
      MIN_AGE = 1.minute

      def run(_input = nil)
        cleaned = 0
        unreachable = 0

        candidate_sessions.find_each do |session|
          detection = QuotaErrorDetector.detect(detection_text_for(session))
          next unless detection.quota_error?

          session.update!(error_message: detection.message)
          session.fail! if session.may_fail?
          cleaned += 1
        rescue ContainerRuntime::ContainerUnreachableError => e
          # The pod behind this session is gone (node died, pod evicted). Its
          # tmux is not coming back, so re-running capture-pane against it every
          # sweep only burns CPU — that spin is what pinned worker-ruby to its
          # HPA ceiling. Skip the session and leave its fate to the session
          # watchdog; one line per session, not one per exec attempt.
          log(:warn, "Skipping session #{session.id}: #{e.message}")
          unreachable += 1
        rescue StandardError => e
          log(:warn, "Failed to process session #{session.id}: #{e.message}")
        end

        { cleaned: cleaned, unreachable: unreachable }
      end

      private

      def candidate_sessions
        TerminalSession
          .where(state: ACTIVE_STATES, session_type: :workflow_step)
          .where.not(container_id: [ nil, "" ])
          .where("COALESCE(started_at, created_at) < ?", MIN_AGE.ago)
      end

      def detection_text_for(session)
        [
          session.error_message,
          live_terminal_output(session)
        ].compact_blank.join("\n")
      end

      def live_terminal_output(session)
        container = runtime.resolve_container(session.container_id)
        return "" unless container

        # exec! (not exec) so a destroyed pod arrives as ContainerUnreachableError
        # instead of an exit code of 1 that looks like an ordinary command failure.
        runtime.exec!(
          container,
          [ "sh", "-c", "tmux capture-pane -t agent -p -S -1000 2>/dev/null || true" ],
          stdout: true, stderr: true
        ).then { |stdout, _stderr, status| status.zero? ? stdout.join("\n") : "" }
      rescue ContainerRuntime::ContainerUnreachableError
        raise
      rescue StandardError => e
        log(:warn, "Failed to read terminal for session #{session.id}: #{e.message}")
        ""
      end

      def runtime
        @runtime ||= ContainerRuntime.build
      end
    end
  end
end
