# frozen_string_literal: true

# Web and MCP start theirs from their Puma configs, the Temporal worker from bin/temporal_worker.
# Each Solid Queue process is forked and has memory of its own.
Rails.application.config.after_initialize do
  SolidQueue.on_start { MemoryStats.start("jobs-supervisor") }
  SolidQueue.on_worker_start { MemoryStats.start("jobs-worker") }
  SolidQueue.on_dispatcher_start { MemoryStats.start("jobs-dispatcher") }
  SolidQueue.on_scheduler_start { MemoryStats.start("jobs-scheduler") }
end
