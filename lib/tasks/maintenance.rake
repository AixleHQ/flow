# frozen_string_literal: true

namespace :maintenance do
  desc "Fail WorkflowRuns stuck in running/paused beyond the stale threshold and terminate their sessions. Set DRY_RUN=true to preview."
  task cleanup_stale_runs: :environment do
    dry_run         = ENV.fetch("DRY_RUN", "false") == "true"
    stale_threshold = Activities::Workflow::CleanupStaleRunsActivity::STALE_THRESHOLD

    puts "[cleanup_stale_runs] dry_run=#{dry_run}, threshold=#{stale_threshold.inspect}"
    puts "[cleanup_stale_runs] scanning for runs stuck in running/paused older than #{stale_threshold.ago} ..."

    stale = WorkflowRun
      .where(state: %w[running paused])
      .where(started_at: ...stale_threshold.ago)

    puts "[cleanup_stale_runs] found #{stale.count} stale run(s)"

    cleaned = 0
    session_failures = 0

    stale.find_each do |run|
      active_sessions = run.step_runs
                           .includes(:terminal_session)
                           .filter_map(&:terminal_session)
                           .select(&:may_fail?)

      puts "[cleanup_stale_runs] run ##{run.id} (#{run.state}, started #{run.started_at}) — #{active_sessions.size} active session(s)"

      next if dry_run

      active_sessions.each do |session|
        SessionService.fail_session(
          session: session,
          error_message: "Terminated by stale run cleanup task (WorkflowRun ##{run.id})"
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

    if dry_run
      puts "[cleanup_stale_runs] DRY RUN complete — no changes written"
    else
      puts "[cleanup_stale_runs] done: #{cleaned} run(s) failed, #{session_failures} session(s) terminated"
    end
  end
end
