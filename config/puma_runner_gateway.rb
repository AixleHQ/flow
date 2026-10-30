# frozen_string_literal: true

# Puma configuration for the runner gateway, /runner/v1/*
# (docs/design/agent-runtimes/DESIGN.md §6.1). The same app on its own port, so
# the long-polls aixle-runner holds open never take a thread from the UI, and
# the gateway scales and is rate-limited on its own.

# Falls back to RAILS_MAX_THREADS, not to a private default: the Active Record
# pool is sized from RAILS_MAX_THREADS (config/settings.yml), so a separate
# default here silently oversubscribes the pool and every thread past the pool
# size dies on ConnectionTimeoutError after the 5s checkout wait.
max_threads_count = ENV.fetch("RUNNER_GATEWAY_MAX_THREADS") { ENV.fetch("RAILS_MAX_THREADS", 10) }
min_threads_count = ENV.fetch("RUNNER_GATEWAY_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

worker_timeout 3600 if ENV.fetch("RAILS_ENV", "development") == "development"

port ENV.fetch("RUNNER_GATEWAY_PORT", 4003)

environment ENV.fetch("RAILS_ENV") { "development" }

pidfile ENV.fetch("RUNNER_GATEWAY_PIDFILE") { "tmp/pids/runner_gateway.pid" }

plugin :tmp_restart

after_booted { MemoryStats.start("runner_gateway") }
