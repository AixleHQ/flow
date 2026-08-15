# frozen_string_literal: true

module Sessions
  # Reads the tail of one session's terminal output — live from the container
  # while it runs, from the stored log once it is over — and says how long the
  # agent has been silent and whether its output ends in a provider quota error.
  #
  # Shared by the personal `get_session_log` tool and the in-session
  # `session_log` tool. Callers own their own default/cap for `lines`: a person
  # debugging a wedged agent wants a screenful, an agent supervising one wants a
  # handful.
  #
  # Never raises for a session that cannot be read: a container that has gone
  # missing is an answer ("unreachable"), not a failure.
  class LogTail
    # How much of a stored log to pull before slicing it to `lines`. The raw
    # capture is a PTY stream with redraw spam, so a generous byte window still
    # yields few useful lines — but it must stay far below the endpoint's 2 MB
    # cap, because this text crosses an MCP transport into someone's context.
    STORED_TAIL_BYTES = 256 * 1024

    # CSI, OSC and two-character escapes. Stored logs are the raw pipe-pane
    # stream; without this a reader gets a screenful of escape codes.
    ANSI_SEQUENCE = /\e\[[0-9;?]*[ -\/]*[@-~]|\e\][^\a\e]*(?:\a|\e\\)|\e[@-Z\\-_]/

    LIVE_STATES = %w[running ready finishing].freeze

    def initialize(session)
      @session = session
    end

    def call(lines:, raw: false)
      payload = live? ? live(lines) : stored(lines, raw: raw)
      payload.merge(quota_verdict(payload[:log]))
    end

    private

    attr_reader :session

    def live?
      session.state.in?(LIVE_STATES) && session.container_id.present?
    end

    def live(lines)
      result = LiveLogReader.new(session).tail(lines: lines)

      case result.status
      when :ok
        { source: "live", log: last_lines(result.text, lines), truncated: false,
          last_output_at: result.last_output_at, idle_seconds: idle_seconds(result.last_output_at) }
      when :not_ready
        { source: "live", log: "", truncated: false,
          last_output_at: result.last_output_at, idle_seconds: idle_seconds(result.last_output_at),
          note: "The container is up but its tmux session is not — it is still starting, or the agent pane has exited." }
      else
        # The pod is gone while the row still says the session is live. That is a
        # finding, not a failure: it is exactly what the dead-container watchdog
        # reacts to, and the caller should hear it as an answer.
        { source: "unreachable", log: "", truncated: false, last_output_at: nil, idle_seconds: nil,
          note: "The session's container is gone. Its state will be corrected by the dead-container watchdog." }
      end
    end

    def stored(lines, raw:)
      log = session.session_logs.find_by(name: "terminal_output.log")
      return no_log_payload if log.nil? || log.file.blank?

      content = read_tail(log)
      content = content.gsub(ANSI_SEQUENCE, "") unless raw

      { source: "stored", log: last_lines(content, lines),
        truncated: log.file_size.to_i > STORED_TAIL_BYTES,
        last_output_at: session.finished_at, idle_seconds: nil }
    end

    def no_log_payload
      { source: "none", log: "", truncated: false, last_output_at: nil, idle_seconds: nil,
        note: "No terminal log was captured for this session." }
    end

    # Seek to the tail on the underlying IO so a large attachment is not loaded
    # whole; fall back to read-then-slice when the storage IO cannot seek (the
    # same shape as Api::V1::TerminalSessionsController#read_log_tail).
    def read_tail(log)
      size = log.file_size.to_i
      log.file.open do |io|
        io.seek(size - STORED_TAIL_BYTES) if size > STORED_TAIL_BYTES
        io.read.to_s
      end
    rescue StandardError
      content = log.file.read.to_s
      content.bytesize > STORED_TAIL_BYTES ? content.byteslice(-STORED_TAIL_BYTES, STORED_TAIL_BYTES).to_s : content
    end

    def last_lines(text, lines)
      text.to_s.lines.last(lines).join
    end

    def idle_seconds(last_output_at)
      return nil if last_output_at.blank?

      [ (Time.current - last_output_at).round, 0 ].max
    end

    # The most common way an agent goes quiet without failing: the provider
    # refused it and the CLI is sitting on the error. Never fatal to the read.
    def quota_verdict(text)
      detection = QuotaErrorDetector.detect(text)
      return {} unless detection.quota_error?

      { quota_error: { provider: detection.provider, message: detection.message } }
    rescue StandardError => e
      Rails.logger.warn("[Sessions::LogTail] quota detection failed: #{e.message}")
      {}
    end
  end
end
