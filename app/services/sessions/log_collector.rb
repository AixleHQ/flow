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
  #
  # The cap itself is gone wherever it can be. It only ever existed because redaction ran
  # here, which forced every byte through this process; now that the container scrubs its
  # own logs as it writes them (docker/base/logger/aixle_redact.py), it can hand them
  # straight to object storage over a presigned PUT and this process only records the key.
  # Two things still take the bounded path, and both on purpose: a container built before
  # those filters shipped, detected rather than assumed, and a log whose CONTENT an
  # adapter parses for usage (#usage_log_paths).
  class LogCollector
    # Chosen against the cleanup phase's 120-second budget, not against storage: the read
    # is one exec per file and the upload one S3 PUT, and several megabytes of either is
    # comfortable where 90 MB is not.
    DEFAULT_MAX_BYTES = 4.megabytes

    # `stat -c` is GNU coreutils, as every agent image is Debian-based — the same
    # assumption LiveLogReader's mtime probe already makes.
    FIELD_SEPARATOR = "|"

    REPORT_NAME = "log-collection-report.txt"

    # Present only in an image carrying the write-time redaction filters. Probed rather
    # than assumed: a session launched from an older image must keep the path where this
    # process does the scrubbing, or its logs reach storage unredacted.
    FILTER_MARKER_PATH = "/opt/mitm/aixle_redact.py"
    FILTERS_FIELD = "__filters__"

    # The container talks to storage directly, so the upload must outlive a slow link
    # without holding the cleanup phase open indefinitely.
    UPLOAD_TIMEOUT_SECONDS = 120

    Result = Struct.new(:count, :contents, :failures, keyword_init: true)

    def initialize(session:, container:, adapter:, runtime:, redactor:,
                   max_bytes: DEFAULT_MAX_BYTES, cache_storage_key: :cache)
      @session = session
      @container = container
      @adapter = adapter
      @runtime = runtime
      @redactor = redactor
      @max_bytes = max_bytes
      # The KEY, not the storage: the signed PUT and the attachment that follows have to
      # name the same one, and the attachment can only name a registered key.
      @cache_storage_key = cache_storage_key
      @failures = []
      # Until the listing says otherwise, assume the container does not scrub its own
      # logs: the safe default is the path where this process does it.
      @container_redacts = false
    end

    def call
      return empty_result if patterns.empty?

      found = list_files
      report_unmatched(found)

      count = 0
      contents = {}

      found.each do |path, size|
        name = File.basename(path)

        if direct_upload?(path) && (uploaded = upload_from_container(path, size, name))
          persist(name, uploaded, size)
          count += 1
          next
        end

        content = read(path, size)
        next if content.nil?

        persist(name, content, content.bytesize)
        contents["logs/#{name}"] = content
        count += 1
      end

      persist_report
      Result.new(count: count + (failures.any? ? 1 : 0), contents: contents, failures: failures)
    end

    private

    attr_reader :session, :container, :adapter, :runtime, :redactor, :max_bytes, :cache_storage_key, :failures

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

        if path == FILTERS_FIELD
          @container_redacts = size.to_i.positive?
          next
        end

        [ path, size.to_i ]
      end
    rescue StandardError => e
      failures << "could not list the declared logs: #{e.class}: #{e.message}"
      []
    end

    # The filter probe rides along in the same exec rather than costing a second
    # pod-exec handshake, which is the expensive part of asking a container anything.
    def list_command
      [
        "/bin/sh", "-c",
        "for f in #{patterns.join(' ')}; do [ -f \"$f\" ] || continue; " \
        "echo \"$f#{FIELD_SEPARATOR}$(stat -c %s \"$f\" 2>/dev/null || echo 0)\"; done; " \
        "[ -f #{FILTER_MARKER_PATH} ] && echo \"#{FILTERS_FIELD}#{FIELD_SEPARATOR}1\" || true"
      ]
    end

    # Whether this file can go straight from the container to storage. Three conditions,
    # each one a way the direct path would otherwise be wrong:
    #
    #   * the container scrubs its own logs. Without that the bytes would reach storage
    #     carrying whatever the agent read through get_config_item — so an image built
    #     before those filters shipped keeps the path where this process scrubs;
    #   * nothing here parses the file. #collect_usage reads some of them
    #     (`artifacts["logs/http.log"]`), and those have to come back through us;
    #   * the storage can sign a PUT at all. In development and test it is a filesystem
    #     or a memory store, and there is nothing to upload to.
    def direct_upload?(path)
      @container_redacts && !usage_log_paths.include?(path) && cache_storage.respond_to?(:presign)
    end

    def usage_log_paths
      @usage_log_paths ||= Array(adapter.try(:usage_log_paths))
    end

    # Hands the container a URL it can PUT to and lets it do the transfer. Nothing about
    # the size of the file reaches this process — which is the whole point: the cap existed
    # because the bytes came through here.
    #
    # --noproxy: every other outbound request in this container goes through the mitm
    # proxy, which would both relay and LOG the upload — writing the log into the log.
    def upload_from_container(path, size, name)
      return nil if size.zero?

      id = "#{SecureRandom.hex(30)}#{File.extname(name)}"
      url = cache_storage.presign(id, method: :put)[:url]

      _stdout, stderr, exit_code = runtime.exec(container, upload_command(path, url), stdout: true, stderr: true)
      unless exit_code.to_i.zero?
        # Not fatal: the caller falls back to reading the file through this process, which
        # is the slower path but still produces a log.
        failures << "#{path} — direct upload failed (exit #{exit_code}#{": #{Array(stderr).join.strip}" if stderr.present?}), fell back to a bounded read"
        return nil
      end

      SessionLogUploader.uploaded_file(
        id: id, storage: cache_storage_key,
        metadata: { "filename" => name, "size" => size,
                    "mime_type" => Marcel::MimeType.for(name: name, extension: File.extname(name)) }
      )
    rescue StandardError => e
      failures << "#{path} — direct upload failed: #{e.class}: #{e.message}, fell back to a bounded read"
      nil
    end

    # Through the uploader, not through Shrine: a Shrine subclass gets its own copy of the
    # storage registry when it is defined, so the two can disagree. The signed PUT and the
    # attachment that follows have to resolve the same key in the same registry, and the
    # attachment can only use this one.
    def cache_storage
      @cache_storage ||= SessionLogUploader.storages[cache_storage_key]
    end

    def upload_command(path, url)
      [
        "/bin/sh", "-c",
        "curl -sS --noproxy '*' --fail --max-time #{UPLOAD_TIMEOUT_SECONDS} " \
        "-X PUT -T #{Shellwords.escape(path)} #{Shellwords.escape(url)}"
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

    # `body` is either the bytes this process read or a file the container has already
    # put in cache storage; in the second case the save promotes it to permanent storage
    # with a server-side copy, so the bytes never travel through here at all.
    #
    # The name is the basename, so the keys adapters already read
    # (`artifacts["logs/http.log"]`) keep working. For a transcript that basename is the
    # agent's own session id, which is the key that correlates this row with the vendor's
    # telemetry.
    def persist(name, body, size)
      log = SessionLog.new(
        terminal_session: session,
        name: name,
        file_size: size,
        content_type: Marcel::MimeType.for(name: name, extension: File.extname(name))
      )

      if body.is_a?(Shrine::UploadedFile)
        log.file_attacher.attach_cached(body)
      else
        log.file = upload(name, body)
      end

      log.save!
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
