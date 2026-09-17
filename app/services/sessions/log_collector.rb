# frozen_string_literal: true

require "shellwords"

module Sessions
  # Collects the log files a session left inside its container, at the end of its life.
  #
  # The previous collector read each declared path with `runtime.read_file`, which copies
  # the whole file out through a tar stream and answers `nil` on any failure — and the
  # caller then did `next if content.blank?`. Both halves were silent, so a file that was
  # simply too large to copy left no log and no trace of having been attempted.
  #
  # In the 14 days to 2026-09-17 that hid two separate things in production:
  #
  #   - `/var/log/mitm/http.log` reached 90 MB in 33 minutes of agent work and was
  #     collected for 438 of 8292 sessions (5%) — only the ones short enough to stay small.
  #     Since `grok`, `cursor_cli` and `codex` price a session by parsing that artifact
  #     (`artifacts["logs/http.log"]`), losing it loses the usage record: 78% of
  #     `cursor_cli` sessions in 30 days carry no UsageStatistic at all.
  #   - Nothing captured the agent's own transcript, so a run that ended wrong could only
  #     be reconstructed from `terminal_output.log` — a raw ANSI redraw stream in which no
  #     tool call is legible.
  #
  # So: read a bounded tail through one exec instead of an unbounded copy, let a
  # declaration be a glob (an agent's transcript is named after its session id), and when
  # a declared log cannot be collected, say so in a file rather than in a log line nobody
  # will still have.
  class LogCollector
    # Chosen against the cleanup phase's 120-second budget, not against storage: the read
    # is one exec per file and the upload one S3 PUT, and several megabytes of either is
    # comfortable where 90 MB is not.
    DEFAULT_MAX_BYTES = 4.megabytes

    # `stat -c` is GNU coreutils, as every agent image is Debian-based — the same
    # assumption LiveLogReader's mtime probe already makes.
    FIELD_SEPARATOR = "|"

    REPORT_NAME = "log-collection-report.txt"

    Result = Struct.new(:count, :contents, :failures, keyword_init: true)

    def initialize(session:, container:, adapter:, runtime:, redactor:, max_bytes: DEFAULT_MAX_BYTES)
      @session = session
      @container = container
      @adapter = adapter
      @runtime = runtime
      @redactor = redactor
      @max_bytes = max_bytes
      @failures = []
    end

    def call
      return empty_result if patterns.empty?

      found = list_files
      report_unmatched(found)

      count = 0
      contents = {}

      found.each do |path, size|
        content = read(path, size)
        next if content.nil?

        name = persist(path, content)
        contents["logs/#{name}"] = content
        count += 1
      end

      persist_report
      Result.new(count: count + (failures.any? ? 1 : 0), contents: contents, failures: failures)
    end

    private

    attr_reader :session, :container, :adapter, :runtime, :redactor, :max_bytes, :failures

    def patterns
      @patterns ||= Array(adapter.session_log_paths).compact_blank
    end

    # One exec for the whole declaration list: the pod-exec handshake is the expensive
    # part, not the commands. Patterns go in unquoted so the container's shell expands the
    # globs; `[ -f ]` then drops both the directories and the patterns that matched
    # nothing and came through literally. They are adapter constants, never user input.
    def list_files
      stdout, _stderr, exit_code = runtime.exec(container, list_command, stdout: true, stderr: true)
      unless exit_code.to_i.zero?
        failures << "could not list the declared logs (exit #{exit_code})"
        return []
      end

      Array(stdout).join.lines.filter_map do |line|
        path, size = line.strip.split(FIELD_SEPARATOR, 2)
        next if path.blank?

        [ path, size.to_i ]
      end
    rescue StandardError => e
      failures << "could not list the declared logs: #{e.class}: #{e.message}"
      []
    end

    def list_command
      [
        "/bin/sh", "-c",
        "for f in #{patterns.join(' ')}; do [ -f \"$f\" ] || continue; " \
        "echo \"$f#{FIELD_SEPARATOR}$(stat -c %s \"$f\" 2>/dev/null || echo 0)\"; done"
      ]
    end

    # A literal path that produced no file is worth saying out loud — it is a declaration
    # the image no longer honours. A glob matching nothing is ordinary: not every session
    # writes a transcript.
    def report_unmatched(found)
      collected = found.map(&:first)
      patterns.each do |pattern|
        next if pattern.include?("*")
        next if collected.include?(pattern)

        failures << "#{pattern} — declared, but no such file in the container"
      end
    end

    def read(path, size)
      # An empty log is a session that wrote nothing, not a collection that went wrong —
      # there is nothing to persist and nothing to report.
      return nil if size.zero?

      stdout, _stderr, exit_code = runtime.exec(container, read_command(path), stdout: true, stderr: true)
      unless exit_code.to_i.zero?
        failures << "#{path} — read failed (exit #{exit_code})"
        return nil
      end

      content = Array(stdout).join
      if content.empty?
        failures << "#{path} — #{size} bytes in the container, nothing came back"
        return nil
      end

      if size > max_bytes
        failures << "#{path} — truncated: kept the last #{max_bytes} of #{size} bytes"
      end

      # Anything the agent echoed — a value it read through get_config_item, most of all —
      # is in these bytes verbatim, and the mitm log carries the full request bodies that
      # travelled to the model. Scrub before any of it is persisted and replayed in the UI.
      redactor.call(content)
    rescue StandardError => e
      failures << "#{path} — read failed: #{e.class}: #{e.message}"
      nil
    end

    def read_command(path)
      [ "/bin/sh", "-c", "tail -c #{max_bytes.to_i} #{Shellwords.escape(path)}" ]
    end

    # The basename, so the keys adapters already read (`artifacts["logs/http.log"]`) keep
    # working. For a transcript that basename is the agent's own session id, which is the
    # key that correlates this row with the vendor's telemetry.
    def persist(path, content)
      name = File.basename(path)
      SessionLog.create!(
        terminal_session: session,
        name: name,
        file: upload(name, content),
        file_size: content.bytesize,
        content_type: Marcel::MimeType.for(name: name, extension: File.extname(name))
      )
      name
    end

    def persist_report
      return if failures.empty?

      text = "Session #{session.id} — logs that could not be collected whole:\n\n" +
             failures.map { |f| "- #{f}\n" }.join

      SessionLog.create!(
        terminal_session: session,
        name: REPORT_NAME,
        file: upload(REPORT_NAME, text),
        file_size: text.bytesize,
        content_type: "text/plain; charset=utf-8"
      )
    rescue StandardError => e
      Rails.logger.warn("[LogCollector] session=#{session.id} could not persist the collection report: #{e.message}")
    end

    def upload(name, content)
      io = StringIO.new(content)
      io.define_singleton_method(:original_filename) { name }
      io
    end

    def empty_result
      Result.new(count: 0, contents: {}, failures: [])
    end
  end
end
