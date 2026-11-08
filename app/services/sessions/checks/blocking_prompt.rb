# frozen_string_literal: true

module Sessions
  module Checks
    # Fails an automatic workflow step parked on a CLI dialog it cannot answer
    # (InteractivePromptDetector, task #605): it would never error and never finish.
    #
    # Only for sessions nobody can rescue by typing: an interactive session's owner can
    # answer the dialog in the web terminal, so failing it would take the decision away
    # from them.
    class BlockingPrompt < Base
      def self.applies_to?(session) = settled_step?(session) && session.mode == "non_interactive"

      def self.parts = %i[scrollback].freeze

      def call(snapshot)
        prompt = InteractivePromptDetector.detect(snapshot.scrollback, agent_type: session.agent_type)
        return continue unless prompt.blocked?

        fail_session(prompt.message)
      end
    end
  end
end
