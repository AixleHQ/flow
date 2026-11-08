# frozen_string_literal: true

module Sessions
  module Checks
    # Sends an automatic session's agent back to work when it ended its turn without
    # `finish_session` (task #208).
    #
    # Automatic sessions run the CLI's TUI, and a TUI whose turn ends waits for a person at
    # its prompt. The agent ends a turn this way after a slip of the model, or because a
    # provider error ended it. Nothing else notices: the step stays `running` until the
    # no-output watchdog fails it, with the session's context lost.
    #
    # Kiro's `Stop` hook was measured first (kiro-cli 3.0.0, TUI) and not used: a `block`
    # makes the agent continue, but the hook runs once per prompt (a second turn end in the
    # same prompt does not run it), it does not run when a provider error ends the turn, and
    # its input names neither the platform session nor whether `finish_session` was called.
    # A typed message is a new prompt, so it works every time and after an error too.
    #
    # A turn end (TurnEndDetector) has to be on two passes, on the same screen, before
    # anything is typed, and then:
    #
    #   - nothing is typed while a person is working in the session's terminal: anyone may
    #     talk to the agent there, and each answer it gives them also ends a turn;
    #   - at most LIMIT reminders per session; the turn end after the last one fails the
    #     session with a message that says so.
    #
    # Kept state: SCREEN_KEY and SEEN_AT_KEY, the screen of the turn end seen on an earlier
    # pass and when. The reminder count (COUNT_KEY) is the action's own: it is written under
    # the session's row lock before anything is typed (#claim).
    class TurnEnd < Base
      LIMIT = 3

      # A person who typed into the terminal this recently is still working there. Input,
      # not an attached client, decides: a browser tab left open must not hold the session.
      PERSON_QUIET = 10.minutes

      # Two passes of the once-a-minute monitor.
      CONFIRM_AFTER = 50.seconds

      MESSAGE = "Aixle: your turn ended, but this automatic session is not finished. " \
                "If all work is done, call `finish_session`. Otherwise continue from where you stopped."

      SCREEN_KEY = "turn_end_screen"
      SEEN_AT_KEY = "turn_end_seen_at"
      COUNT_KEY = "turn_end_nudges"

      def self.applies_to?(session)
        settled_step?(session) &&
          session.mode == "non_interactive" &&
          session.state == "ready" &&
          !Sessions::AuthPause.paused?(session)
      end

      def self.parts = %i[scrollback clients].freeze

      def self.kept_keys = [ SCREEN_KEY, SEEN_AT_KEY ].freeze

      def self.message_after_limit
        "Session terminated: the agent ended its turn without calling `finish_session` " \
          "#{LIMIT + 1} times, and Aixle's #{LIMIT} reminders to finish or continue did not change that. " \
          "The last turn is at the end of the session's terminal."
      end

      def call(snapshot)
        return continue if snapshot.scrollback.blank?

        unless TurnEndDetector.idle?(snapshot.scrollback, agent_type: session.agent_type)
          forget
          return continue
        end

        digest = snapshot.screen_digest
        return remember(digest) unless confirmed?(digest)
        return continue(:pending) if person_working?(snapshot)
        return give_up if nudges >= LIMIT
        return continue(:pending) unless claim(digest)

        unless PaneInput.type(session, MESSAGE, runtime: runtime)
          log(:warn, "could not type reminder #{nudges}/#{LIMIT}; it counts toward the limit")
          return continue(:pending)
        end

        log(:info, "nudged (#{nudges}/#{LIMIT})")
        stop(:nudged)
      end

      private

      def nudges
        (session.metadata || {})[COUNT_KEY].to_i
      end

      def confirmed?(digest)
        return false unless kept[SCREEN_KEY] == digest

        seen_at = Time.zone.parse(kept[SEEN_AT_KEY].to_s)
        seen_at.present? && seen_at <= CONFIRM_AFTER.ago
      end

      def remember(digest)
        kept.store(SCREEN_KEY => digest, SEEN_AT_KEY => Time.current.iso8601)
        continue(:pending)
      end

      def forget
        kept.delete(SCREEN_KEY, SEEN_AT_KEY)
      end

      # Takes this confirmed turn end for one reminder, before anything is typed. Under the
      # session's row lock it checks again that the session still takes reminders, that the
      # confirmed screen is still the recorded one and that one is left, then counts the
      # reminder and forgets the screen. A Temporal retry of the pass, or a second pass
      # reading the same screen, then finds no confirmed screen and types nothing. The cost
      # is that a reminder whose typing failed is used up, and the next turn end gets the
      # next one: a lost reminder is better than a repeated one.
      def claim(digest)
        session.with_lock do
          next false unless self.class.applies_to?(session) && session.metadata&.dig(SCREEN_KEY) == digest &&
                            nudges < LIMIT

          session.update_jsonb_keys!(:metadata, set: { COUNT_KEY => nudges + 1 }, remove: [ SCREEN_KEY, SEEN_AT_KEY ])
          true
        end
      end

      # Fails the session after its last reminder, if it still takes reminders and has used
      # them all (Base#fail_session).
      def give_up
        result = fail_session(self.class.message_after_limit) { |locked| locked.metadata&.dig(COUNT_KEY).to_i >= LIMIT }
        log(:info, "stopped again after #{LIMIT} reminders; failed") if result.outcome == :failed
        result
      end

      # True when a writable client typed within PERSON_QUIET, and when the clients could
      # not be read: typing over a person is worse than waiting a minute for the next pass.
      def person_working?(snapshot)
        clients = snapshot.clients
        return true if clients.nil?

        clients.input_within?(PERSON_QUIET)
      end
    end
  end
end
