# frozen_string_literal: true

require "test_helper"

module Sessions
  class LogSourceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @session = create(:terminal_session, :agent_session, user: @user)
    end

    def source_for(content)
      io = StringIO.new(content)
      io.define_singleton_method(:original_filename) { "http.log" }
      log = SessionLog.create!(terminal_session: @session, name: "http.log", file: io,
                               file_size: content.bytesize, content_type: "text/plain")
      LogSource.new(log.file, size: content.bytesize)
    end

    test "yields the same lines a String would" do
      content = "first\nsecond\nthird\n"

      assert_equal content.each_line.to_a, source_for(content).each_line.to_a
    end

    test "keeps a trailing line that has no newline" do
      assert_equal [ "a\n", "b" ], source_for("a\nb").each_line.to_a
    end

    test "reassembles a line split across two reads" do
      line = "x" * (LogSource::CHUNK_BYTES + 100)
      content = "#{line}\ntail\n"

      assert_equal [ "#{line}\n", "tail\n" ], source_for(content).each_line.to_a
    end

    test "keeps a multi-byte character whole across a read boundary" do
      # Land the second byte of "я" on the far side of the chunk boundary.
      padding = "x" * (LogSource::CHUNK_BYTES - 1)
      content = "#{padding}я\n"

      lines = source_for(content).each_line.to_a

      assert_equal 1, lines.size
      assert_equal Encoding::UTF_8, lines.first.encoding
      assert lines.first.valid_encoding?
      assert_equal content, lines.first
    end

    # CodexAdapter makes two passes over the same log, one for OTLP metrics and one for
    # the raw exchanges.
    test "can be read more than once" do
      source = source_for("a\nb\n")

      assert_equal 2, source.each_line.to_a.size
      assert_equal 2, source.each_line.to_a.size
    end

    test "reports emptiness the way a String does, without opening anything" do
      source = LogSource.new(nil, size: 0)

      assert source.blank?
      assert_not source.present?
      assert_equal 0, source.bytesize
      assert_empty source.each_line.to_a
    end

    test "carries the size the listing reported" do
      assert_equal 19, source_for("first\nsecond\nthird\n").bytesize
    end
  end
end
