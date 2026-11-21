# frozen_string_literal: true

module Sessions
  module Checks
    # Fails an automatic workflow step whose agent CLI has exited, with its exit status and
    # what it printed last (task #324: Cursor CLI refused `composer-2.5[effort=low]` and
    # the step sat until a person cancelled the run). Such a step can no longer call
    # `finish_session`, so waiting only delays the failure, and the no-output watchdog's
    # message would name a dialog that is not there.
    #
    # An automatic session's CLI is the agent pane's own process, kept once it exits
    # (AgentSessionStrategy#launch_agent_in_tmux), so tmux reports the exit: no text on the
    # screen is read to decide it. An interactive session's CLI runs in a shell its person
    # can start it again from, so it is left alone.
    class AgentExited < Base
      MAX_MESSAGE_LENGTH = 500

      def self.applies_to?(session) = settled_step?(session) && session.ready? && session.mode == "non_interactive"

      def self.parts = %i[agent_exit].freeze

      def call(snapshot)
        exited = snapshot.agent_exit
        return continue unless exited&.dead?

        fail_session(message(exited))
      end

      private

      def message(exited)
        reason = "Session terminated: the agent CLI exited with status #{exited.status} " \
                 "without calling `finish_session`."
        output = exited.output
        reason += " Its last output: #{output}" if output.present?
        reason.truncate(MAX_MESSAGE_LENGTH)
      end
    end
  end
end
