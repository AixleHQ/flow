# frozen_string_literal: true

# Logs a long-running process's memory every few minutes, so a leak shows up as a
# trend in the logs within a day rather than as OOMKilled pods. Live slots and old
# objects that keep climbing mean Ruby objects are being retained; RSS climbing
# while they stay flat means native memory.
module MemoryStats
  INTERVAL = 5.minutes

  module_function

  def start(role)
    return if Rails.env.local?

    Thread.new do
      Thread.current.name = "memory-stats"
      loop do
        sleep INTERVAL
        Rails.logger.info(line(role))
      rescue StandardError => e
        Rails.logger.warn("[MemoryStats] #{e.class}: #{e.message}")
      end
    end
  end

  def line(role)
    gc = GC.stat
    "[memory] role=#{role} pid=#{Process.pid} rss_mib=#{rss_mib} heap_live_slots=#{gc[:heap_live_slots]} " \
      "old_objects=#{gc[:old_objects]} heap_pages=#{gc[:heap_allocated_pages]} major_gc=#{gc[:major_gc_count]} " \
      "minor_gc=#{gc[:minor_gc_count]} malloc_increase_bytes=#{gc[:malloc_increase_bytes]}"
  end

  def rss_mib
    File.read("/proc/self/status")[/^VmRSS:\s+(\d+)/, 1].to_i / 1024
  rescue Errno::ENOENT
    nil
  end
end
