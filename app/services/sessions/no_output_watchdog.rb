# frozen_string_literal: true

module Sessions
  # Decides whether a session has been silent for too long.
  #
  # Silence is judged by the rendered screen, not by bytes. The container's
  # /tmp/terminal_output.log (tmux pipe-pane) grows with every byte the pane sends,
  # and an idle TUI sends bytes that change nothing: Kiro repaints its whole unchanged
  # screen when the pane is resized, which an attached web terminal does. Judged by the
  # log's mtime, a session parked at its prompt read as busy for 80 minutes (task #208).
  #
  # So each read keeps a digest of the screen (ScreenDigest) on the session and the time
  # it last changed. A screen cannot change without bytes, so the log's mtime still bounds
  # that time from above: a first read, or a read of a changed screen, starts from it.
  # When the screen has not changed for NO_OUTPUT_THRESHOLD the session is stuck: blocked
  # on an interactive prompt, parked at its prompt after a turn that ended without
  # `finish_session`, or dead without signalling. A working session keeps its screen
  # changing: Kiro shows `Kiro is working · 1m 15s`, Claude Code and Codex a ticking timer.
  class NoOutputWatchdog
    NO_OUTPUT_THRESHOLD = 30.minutes

    # Enough of the pane to carry the banner a stalled CLI last printed. The mtime the
    # staleness check needs comes with the same read, so naming the cause costs nothing.
    TAIL_LINES = 40

    SCREEN_KEY = "screen_digest"
    SCREEN_CHANGED_AT_KEY = "screen_changed_at"

    def initialize(session, runtime: nil)
      @session = session
      @runtime = runtime
    end

    def stale?
      silent_for?(NO_OUTPUT_THRESHOLD)
    end

    # Whether the screen has not changed for at least `duration`. Callers other than the
    # watchdog use a shorter one: the token-refresh sweep asks it to tell a session that
    # is merely parked at a prompt from one with an agent mid-turn, because rotating a
    # grant under the first is recoverable and under the second is not. Both callers'
    # reads feed the same record, so either one's earlier look counts for the other.
    # False when the container cannot be read — "unknown" must never read as "idle".
    def silent_for?(duration)
      changed_at = screen_changed_at
      changed_at.present? && changed_at < duration.ago
    end

    # Why the session is being terminated. "No output" is the symptom; when the pane still
    # shows an expired-login banner it is also the cause, and saying so is the difference
    # between "the agent went quiet" and "reconnect this agent". 41% of the sessions this
    # watchdog reaped in the 14 days to 2026-09-17 carried such a banner.
    def message
      auth = AuthErrorDetector.detect(tail.text)
      return "Session terminated: agent authentication failed — #{auth.message}" if auth.auth_error?

      if TurnEndDetector.idle?(tail.text, agent_type: session.agent_type)
        return "Session terminated: the agent ended its turn without calling `finish_session`, " \
               "and its terminal has not changed for #{NO_OUTPUT_THRESHOLD.inspect}."
      end

      "Session terminated: no output for #{NO_OUTPUT_THRESHOLD.inspect}. " \
        "The agent may be blocked on an interactive prompt (e.g. a spend-limit dialog)."
    end

    private

    attr_reader :session, :runtime

    def screen_changed_at
      return @screen_changed_at if defined?(@screen_changed_at)

      @screen_changed_at = observe_screen
    end

    def observe_screen
      return nil unless tail.status == :ok
      return nil if tail.last_output_at.nil?

      digest = ScreenDigest.of(tail.text)
      metadata = session.metadata || {}
      recorded = Time.zone.parse(metadata[SCREEN_CHANGED_AT_KEY].to_s) if metadata[SCREEN_KEY] == digest
      return [ recorded, tail.last_output_at ].min if recorded

      session.merge_jsonb!(:metadata, SCREEN_KEY => digest, SCREEN_CHANGED_AT_KEY => tail.last_output_at.iso8601)
      tail.last_output_at
    end

    # One read serves both the verdict and its explanation: the pane is fetched by an exec
    # into the container, and a second one could see a different pane.
    def tail
      @tail ||= reader.tail(lines: TAIL_LINES)
    end

    def reader
      @reader ||= Sessions::LiveLogReader.new(session, runtime: @runtime)
    end
  end
end
