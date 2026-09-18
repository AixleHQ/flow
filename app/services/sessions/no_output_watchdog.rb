# frozen_string_literal: true

module Sessions
  # Decides whether a session has been silent for too long.
  # Uses the terminal_output.log mtime (via LiveLogReader) as a proxy for
  # "last agent output" — the log is updated by tmux pipe-pane on the container
  # whenever the pane produces new bytes. When the mtime is older than
  # NO_OUTPUT_THRESHOLD the session is stuck: either blocked on an interactive
  # prompt (quota/spend-limit dialog) or dead without signalling.
  class NoOutputWatchdog
    NO_OUTPUT_THRESHOLD = 30.minutes

    # Enough of the pane to carry the banner a stalled CLI last printed. The mtime the
    # staleness check needs comes with the same read, so naming the cause costs nothing.
    TAIL_LINES = 40

    def initialize(session, runtime: nil)
      @session = session
      @runtime = runtime
    end

    def stale?
      silent_for?(NO_OUTPUT_THRESHOLD)
    end

    # Whether the pane has been quiet for at least `duration`. Callers other than the
    # watchdog use a shorter one: the token-refresh sweep asks it to tell a session that
    # is merely parked at a prompt from one with an agent mid-turn, because rotating a
    # grant under the first is recoverable and under the second is not.
    # False when the container cannot be read — "unknown" must never read as "idle".
    def silent_for?(duration)
      return false unless tail.status == :ok
      return false if tail.last_output_at.nil?

      tail.last_output_at < duration.ago
    end

    # Why the session is being terminated. "No output" is the symptom; when the pane still
    # shows an expired-login banner it is also the cause, and saying so is the difference
    # between "the agent went quiet" and "reconnect this agent". 41% of the sessions this
    # watchdog reaped in the 14 days to 2026-09-17 carried such a banner.
    def message
      auth = AuthErrorDetector.detect(tail.text)
      return "Session terminated: agent authentication failed — #{auth.message}" if auth.auth_error?

      "Session terminated: no output for #{NO_OUTPUT_THRESHOLD.inspect}. " \
        "The agent may be blocked on an interactive prompt (e.g. a spend-limit dialog)."
    end

    private

    attr_reader :session, :runtime

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
