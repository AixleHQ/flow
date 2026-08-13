# frozen_string_literal: true
#
# One-shot backlog cleanup for WorkflowRuns stuck in running/paused.
#
# Usage (production):
#   docker compose exec -T web bin/rails runner db/maintenance/cleanup_stale_runs.rb
#
# Safe to re-run: already-terminal runs are excluded by the scope.
# The STALE_THRESHOLD matches CleanupStaleRunsActivity — change both if adjusting.

STALE_THRESHOLD = 4.hours
DRY_RUN = ENV.fetch("DRY_RUN", "false") == "true"

puts "[cleanup_stale_runs] dry_run=#{DRY_RUN}, threshold=#{STALE_THRESHOLD.inspect}"
puts "[cleanup_stale_runs] scanning for runs stuck in running/paused older than #{STALE_THRESHOLD.ago} ..."

stale = WorkflowRun
  .where(state: %w[running paused])
  .where(started_at: ...STALE_THRESHOLD.ago)

puts "[cleanup_stale_runs] found #{stale.count} stale run(s)"

cleaned = 0
session_failures = 0

stale.find_each do |run|
  active_sessions = run.step_runs
                       .includes(:terminal_session)
                       .filter_map(&:terminal_session)
                       .select(&:may_fail?)

  puts "[cleanup_stale_runs] run ##{run.id} (#{run.state}, started #{run.started_at}) — #{active_sessions.size} active session(s)"

  next if DRY_RUN

  active_sessions.each do |session|
    SessionService.fail_session(
      session: session,
      error_message: "Terminated by stale run cleanup script (WorkflowRun ##{run.id})"
    )
    session_failures += 1
    puts "  -> failed session ##{session.id}"
  rescue StandardError => e
    puts "  -> ERROR failing session ##{session.id}: #{e.message}"
  end

  run.update_column(:failure_reason, "stale_run")
  run.fail! if run.may_fail?
  cleaned += 1
  puts "  -> run ##{run.id} transitioned to failed"
rescue StandardError => e
  puts "  -> ERROR processing run ##{run.id}: #{e.message}"
end

if DRY_RUN
  puts "[cleanup_stale_runs] DRY RUN complete — no changes written"
else
  puts "[cleanup_stale_runs] done: #{cleaned} run(s) failed, #{session_failures} session(s) terminated"
end
