# frozen_string_literal: true

module Sessions
  module Checks
    # Fails an automatic workflow step whose agent CLI has exited (AgentExitDetector, task
    # #324), with what the CLI printed as the reason. Such a step can no longer call
    # `finish_session`, so waiting only delays the failure, and the no-output watchdog's
    # message would name a dialog that is not there.
    #
    # Only for sessions nobody watches: in an interactive session the person can start the
    # CLI again in the same shell.
    class AgentExited < Base
      MAX_MESSAGE_LENGTH = 500

      def self.applies_to?(session) = settled_step?(session) && session.ready? && session.mode == "non_interactive"

      def self.parts = %i[scrollback].freeze

      def call(snapshot)
        exited = AgentExitDetector.detect(snapshot.scrollback)
        return continue unless exited.exited?

        fail_session(message(exited))
      end

      private

      def message(exited)
        reason = "Session terminated: the agent CLI exited with status #{exited.status} " \
                 "without calling `finish_session`."
        reason += " Its last output: #{exited.output}" if exited.output.present?
        reason.truncate(MAX_MESSAGE_LENGTH)
      end
    end
  end
end
