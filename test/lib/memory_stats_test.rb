# frozen_string_literal: true

require "test_helper"

class MemoryStatsTest < ActiveSupport::TestCase
  test "a line names the process and carries the figures that tell retained objects from native memory" do
    line = MemoryStats.line("web")

    assert_match(/\A\[memory\] role=web pid=#{Process.pid} rss_mib=\d*/, line)
    assert_match(/heap_live_slots=\d+ old_objects=\d+ heap_pages=\d+ major_gc=\d+ minor_gc=\d+ malloc_increase_bytes=\d+\z/, line)
  end

  test "it does not start in development or test" do
    assert_nil MemoryStats.start("web")
  end
end
