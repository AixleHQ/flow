# frozen_string_literal: true

module PersonalTools
  class GetSessionLog < Base
    tool do
      display_name "Get Session Log"
      description "Return the tail of one session's terminal output — read live from the container " \
                  "while it runs, from the stored log once it is over — together with how long the " \
                  "agent has been silent and whether its output ends in a provider quota error. " \
                  "This is the tool for telling a working agent from a wedged one; list_sessions " \
                  "gives you the id."
      audience :user
      tags :sessions
      read_only
      param :session_id, type: :integer, description: "Session id, from list_sessions.", required: true
      param :lines, type: :integer, description: "Tail size in lines (default 200, cap 2000)."
      param :raw, type: :boolean,
                  description: "Keep ANSI escape sequences in a stored log (default false). Live " \
                               "reads are already plain text."
    end

    DEFAULT_LINES = 200
    MAX_LINES = 2_000

    # How much of a stored log to pull before slicing it to `lines`. The raw
    # capture is a PTY stream with redraw spam, so a generous byte window still
    # yields few useful lines — but it must stay far below the endpoint's 2 MB
    # cap, because this text crosses an MCP transport into someone's context.
    STORED_TAIL_BYTES = 256 * 1024

    # CSI, OSC and two-character escapes. Stored logs are the raw pipe-pane
    # stream; without this an agent gets a screenful of escape codes.
    ANSI_SEQUENCE = /\e\[[0-9;?]*[ -\/]*[@-~]|\e\][^\a\e]*(?:\a|\e\\)|\e[@-Z\\-_]/

    LIVE_STATES = %w[running ready finishing].freeze

    def execute
      session = find_session!
      lines = requested_lines
      payload = live?(session) ? live(session, lines) : stored(session, lines)

      success(base_payload(session).merge(payload).merge(quota_verdict(payload[:log])))
    end

    private

    def requested_lines
      requested = params[:lines].present? ? params[:lines].to_i : DEFAULT_LINES
      requested.clamp(1, MAX_LINES)
    end

    def live?(session)
      session.state.in?(LIVE_STATES) && session.container_id.present?
    end

    def base_payload(session)
      {
        session_id: session.id,
        state: session.state,
        session_type: session.session_type,
        agent_type: session.agent_type,
        mode: session.mode,
        project_id: session.project_id,
        started_at: session.started_at,
        finished_at: session.finished_at,
        error_message: session.error_message
      }
    end

    def live(session, lines)
      result = ::Sessions::LiveLogReader.new(session).tail(lines: lines)

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

    def stored(session, lines)
      log = session.session_logs.find_by(name: "terminal_output.log")
      return no_log_payload if log.nil? || log.file.blank?

      content = read_tail(log)
      content = content.gsub(ANSI_SEQUENCE, "") unless params[:raw]

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
      Rails.logger.warn("[GetSessionLog] quota detection failed: #{e.message}")
      {}
    end
  end
end
