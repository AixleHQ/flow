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

    def initialize(session, runtime: nil)
      @session = session
      @runtime = runtime
    end

    def stale?
      result = reader.tail(lines: 1)
      return false unless result.status == :ok
      return false if result.last_output_at.nil?

      result.last_output_at < NO_OUTPUT_THRESHOLD.ago
    end

    def message
      "Session terminated: no output for #{NO_OUTPUT_THRESHOLD.inspect}. " \
        "The agent may be blocked on an interactive prompt (e.g. a spend-limit dialog)."
    end

    private

    attr_reader :session, :runtime

    def reader
      @reader ||= Sessions::LiveLogReader.new(session, runtime: @runtime)
    end
  end
end
