# frozen_string_literal: true

module Sessions
  module Checks
    # Fails an unattended workflow step that has been silent for NO_OUTPUT_THRESHOLD: blocked
    # on an interactive prompt (quota / spend-limit dialog) that shows no error text, parked
    # at its prompt after a turn that ended without `finish_session`, or dead without
    # signalling.
    #
    # Silence is judged by the rendered screen, not by bytes. The container's
    # /tmp/terminal_output.log (tmux pipe-pane) grows with every byte the pane sends, and an
    # idle TUI sends bytes that change nothing: Kiro repaints its whole unchanged screen when
    # the pane is resized, which an attached web terminal does. Judged by the log's mtime, a
    # session parked at its prompt read as busy for 80 minutes (task #208).
    #
    # So each pass keeps a digest of the screen (ScreenDigest) and the time it last changed.
    # A screen cannot change without bytes, so the log's mtime still bounds that time from
    # above: a first read, or a read of a changed screen, starts from it. A working session
    # keeps its screen changing: Kiro shows `Kiro is working · 1m 15s`.
    #
    # The screen rule applies only to the runtimes in SCREEN_RULE_RUNTIMES, whose working
    # screen was measured to change on every read. Every other runtime keeps the log-mtime
    # rule: an indicator that animates only through colour, or a spinner without a timer,
    # can give the same capture on two reads while the agent works, and the screen rule
    # would then reap a working session and let the token-refresh sweep rotate a grant under
    # an agent mid-turn.
    #
    # An interactive step is left alone: silence is what one looks like while its person
    # reviews the work, and whoever is watching can answer a dialog in the web terminal. So
    # is a step waiting for its agent's login to be renewed: Sessions::AuthPause bounds that
    # wait itself. Every other `ready` step is read from its start, however young, so the
    # first pass starts the screen's record.
    #
    # Kept state: SCREEN_KEY and SCREEN_CHANGED_AT_KEY, for the screen-rule runtimes.
    class NoOutput < Base
      NO_OUTPUT_THRESHOLD = 30.minutes

      # Opt-in, like TurnEndDetector::SIGNATURES: a runtime joins once its working screen,
      # tool calls included, has been captured on its pinned CLI and shown to change.
      SCREEN_RULE_RUNTIMES = %w[kiro_cli].freeze

      SCREEN_KEY = "screen_digest"
      SCREEN_CHANGED_AT_KEY = "screen_changed_at"

      def self.applies_to?(session)
        session.session_type == "workflow_step" &&
          session.state == "ready" &&
          session.mode != "interactive" &&
          session.container_id.present? &&
          !Sessions::AuthPause.paused?(session)
      end

      def self.parts = %i[scrollback log_mtime].freeze

      def self.kept_keys = [ SCREEN_KEY, SCREEN_CHANGED_AT_KEY ].freeze

      def self.screen_rule?(agent_type)
        SCREEN_RULE_RUNTIMES.include?(agent_type.to_s)
      end

      def call(snapshot)
        return continue unless silent_for?(snapshot, NO_OUTPUT_THRESHOLD)

        fail_session(message(snapshot))
      end

      # Whether the screen has not changed for at least `duration`; for a runtime outside
      # SCREEN_RULE_RUNTIMES, whether the log got no bytes for that long. The token-refresh
      # sweep asks it with a shorter one, on an on-demand snapshot, to tell a session merely
      # parked at a prompt from one with an agent mid-turn. Both callers' reads feed the same
      # record, so either one's earlier look counts for the other. False when the container
      # cannot be read: "unknown" must never read as "idle".
      def silent_for?(snapshot, duration)
        changed_at = screen_changed_at(snapshot)
        changed_at.present? && changed_at < duration.ago
      end

      private

      def screen_changed_at(snapshot)
        last_output_at = snapshot.last_output_at
        return nil if last_output_at.nil?
        return last_output_at unless self.class.screen_rule?(session.agent_type)

        digest = snapshot.screen_digest
        recorded = Time.zone.parse(kept[SCREEN_CHANGED_AT_KEY].to_s) if kept[SCREEN_KEY] == digest
        return [ recorded, last_output_at ].min if recorded

        kept.store(SCREEN_KEY => digest, SCREEN_CHANGED_AT_KEY => last_output_at.iso8601)
        last_output_at
      end

      # Why the session is being terminated. "No output" is the symptom; when the pane still
      # shows an expired-login banner it is also the cause, and saying so is the difference
      # between "the agent went quiet" and "reconnect this agent". 41% of the sessions this
      # watchdog reaped in the 14 days to 2026-09-17 carried such a banner.
      def message(snapshot)
        auth = AuthErrorDetector.detect(snapshot.screen.join("\n"))
        return "Session terminated: agent authentication failed — #{auth.message}" if auth.auth_error?

        if TurnEndDetector.idle?(snapshot.scrollback, agent_type: session.agent_type)
          return "Session terminated: the agent ended its turn without calling `finish_session`, " \
                 "and its terminal has not changed for #{NO_OUTPUT_THRESHOLD.inspect}."
        end

        "Session terminated: no output for #{NO_OUTPUT_THRESHOLD.inspect}. " \
          "The agent may be blocked on an interactive prompt (e.g. a spend-limit dialog)."
      end
    end
  end
end
