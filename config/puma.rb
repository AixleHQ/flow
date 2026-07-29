# Puma can serve each request in a thread from an internal thread pool.
# The `threads` method setting takes two numbers: a minimum and maximum.
# Any libraries that use thread pools should be configured to match
# the maximum value specified for Puma. Default is set to 5 threads for minimum
# and maximum; this matches the default thread size of Active Record.
#
max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 10)
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Specifies the `worker_timeout` threshold that Puma will use to wait before
# terminating a worker in development environments.
#
worker_timeout 3600 if ENV.fetch("RAILS_ENV", "development") == "development"

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
#
port ENV.fetch("PORT", 4000)
# bind "tcp://0.0.0.0:#{ENV['PORT'] || 4000}"

# Specifies the `environment` that Puma will run in.
#
environment ENV.fetch("RAILS_ENV") { "development" }

# Specifies the `pidfile` that Puma will use.
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

# Specifies the number of `workers` to boot in clustered mode.
# Workers are forked web server processes. If using threads and workers together
# the concurrency of the application would be max `threads` * `workers`.
# Workers do not work on JRuby or Windows (both of which do not support
# processes).
#
# workers ENV.fetch("WEB_CONCURRENCY") { 2 }

# Use the `preload_app!` method when specifying a `workers` number.
# This directive tells Puma to first boot the application and load code
# before forking the application. This takes advantage of Copy On Write
# process behavior so workers use less memory.
#
# preload_app!

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside Puma, ON BY DEFAULT.
#
# Deliberately opt-OUT rather than opt-in: production deployments are managed
# outside this repository, so nothing here can add a dedicated jobs process, and
# an opt-in flag that someone forgets to set means jobs pile up in the database
# with no one running them — mail simply stops, silently. Defaulting to on makes
# the failure mode "jobs run in an extra place", which is harmless: Solid Queue
# coordinates through the database, so one supervisor per web replica is a
# supported topology.
#
# Only this config is affected. config/puma_mcp.rb is a separate file that never
# loads this one, so the MCP server does not pick up a supervisor.
#
# Set SOLID_QUEUE_IN_PUMA=false where something else runs the jobs.
plugin :solid_queue unless ENV["SOLID_QUEUE_IN_PUMA"] == "false"
