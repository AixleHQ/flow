# Puma configuration for the dedicated MCP (Model Context Protocol) server.
# Runs on a separate port to isolate MCP traffic from the main web server.

max_threads_count = ENV.fetch("MCP_MAX_THREADS", 10)
min_threads_count = ENV.fetch("MCP_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

worker_timeout 3600 if ENV.fetch("RAILS_ENV", "development") == "development"

port ENV.fetch("MCP_PORT", 4002)

environment ENV.fetch("RAILS_ENV") { "development" }

pidfile ENV.fetch("MCP_PIDFILE") { "tmp/pids/mcp.pid" }

plugin :tmp_restart
