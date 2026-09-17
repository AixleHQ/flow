# frozen_string_literal: true

module Sessions
  # A stored session log, read a line at a time.
  #
  # `#collect_usage` prices a session by parsing `/var/log/mitm/http.log`, which reaches
  # 90 MB in half an hour of agent work. It used to receive that as a String, which is why
  # the log had to be copied out of the container and held whole in this process — and
  # copying it is what failed: over the 30 days to 2026-09-17, cleanup ran for 277 of the
  # 281 `cursor_cli`/`grok`/`codex` sessions and only 52 of them ever produced an
  # `http.log` row, the largest 2.04 MB. Exactly one session in that window failed *in*
  # the cleanup phase. The ceiling was the transfer, not the time budget.
  #
  # So the container uploads the file whole and this reads it back in chunks. Every parser
  # was already written as `log_content.each_line`, which is the only thing this has to
  # be — and a String is still one, so a log small enough to have come through this
  # process needs no wrapping and no adapter knows the difference.
  class LogSource
    CHUNK_BYTES = 1.megabyte

    attr_reader :bytesize

    def initialize(file, size:)
      @file = file
      @bytesize = size.to_i
    end

    def blank? = bytesize.zero?
    def present? = !blank?

    # Re-readable on purpose: CodexAdapter makes two passes, one for the CLI's OTLP
    # metrics and one for the raw exchanges, and each opens the object again rather than
    # holding it between them.
    def each_line
      return enum_for(:each_line) unless block_given?
      return if blank?

      buffer = +""
      file.open do |io|
        while (chunk = io.read(CHUNK_BYTES))
          break if chunk.empty?

          buffer << chunk.b
          while (newline = buffer.index("\n"))
            yield finish(buffer.slice!(0, newline + 1))
          end
        end
      end

      yield finish(buffer) unless buffer.empty?
      nil
    end

    private

    attr_reader :file

    # Encoding is fixed per line rather than per chunk: a multi-byte character split
    # across two reads is still whole by the time a line is complete.
    def finish(line)
      line.force_encoding(Encoding::UTF_8).scrub
    end
  end
end
