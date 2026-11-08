# frozen_string_literal: true

module Sessions
  module Checks
    # Fails a workflow step whose CLI stopped on its provider's quota or credit error
    # (QuotaErrorDetector), so it does not wait out the no-output watchdog.
    #
    # The session's recorded error message counts as it is. The pane counts only for the
    # session's own provider, only on its current screen, and only once it has gone quiet:
    # the pane is mostly the agent's work, and that work can print the very text these
    # patterns look for (task #195: a grep of ShowPage.tsx failed a Kiro session with an
    # OpenAI identifier). A CLI stopped on quota prints nothing more.
    #
    # Applies to interactive steps too: a quota stop is not something a person can answer.
    class QuotaError < Base
      def self.applies_to?(session) = settled_step?(session)

      def self.parts = %i[scrollback log_mtime].freeze

      def call(snapshot)
        detection = recorded || on_screen(snapshot)
        return continue if detection.nil?

        fail_session(detection.message)
      end

      private

      def recorded
        detection = QuotaErrorDetector.detect(session.error_message, agent_type: session.agent_type)
        detection if detection.quota_error?
      end

      def on_screen(snapshot)
        detection = QuotaErrorDetector.detect_on_screen(snapshot.scrollback, agent_type: session.agent_type)
        detection if detection.quota_error? && snapshot.quiet_for?(QuotaErrorDetector::QUIET_BEFORE_FAIL)
      end
    end
  end
end
