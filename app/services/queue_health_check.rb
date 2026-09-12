# frozen_string_literal: true

# Watches whether work is actually moving, from a process that is not the one
# doing the moving.
#
# WHY IT DOES NOT LIVE IN TEMPORAL: every other recurring job in this app is a
# Temporal schedule executed by the worker (config/queue.yml says so, and that
# convention is right for work). This one is not work, it is the watch — and on
# 2026-09-12 the worker itself was what failed. Its Sentry interceptor, the
# admission reconciler, the quota and no-output scanners, the outbox relay: every
# safety net in the installation was a Temporal schedule, so they all stopped
# together, silently, and nothing noticed for nearly two hours. A watchdog hosted
# by the thing it watches is not a watchdog. This one runs in the Solid Queue
# supervisor (the `jobs` deployment), which stayed up throughout.
#
# WHAT IT WATCHES: symptoms, not liveness. "Is a worker polling?" is a question
# with a fragile answer; "has any run been sitting unstarted for five minutes?" is
# a question the database can answer alone, it is the thing the queue is sold on,
# and it is true whatever the cause — a crashed worker, an unreachable Temporal, a
# wedged task queue, or something nobody has thought of yet.
class QueueHealthCheck
  # A run the worker has not started. Normally this is seconds: the run row and
  # the Temporal execution are created in the same call, and the first activity
  # follows immediately. Queueing for capacity happens one level down, at the
  # session — an admitted run whose step is waiting for a slot is `running`, not
  # `pending` — so nothing legitimate parks a run here.
  UNSTARTED_RUN_THRESHOLD = 5.minutes

  # A session that has waited this long for a slot is not necessarily wrong — a
  # full pool is the feature working — but it is worth seeing, because "the pool
  # is full" and "the pool is full of reservations nothing will ever release" look
  # identical from outside.
  ADMISSION_WAIT_THRESHOLD = 30.minutes

  class << self
    def call(now: Time.current)
      stats = snapshot(now: now)
      report(stats)
      stats
    end

    def snapshot(now: Time.current)
      unstarted = WorkflowRun.where(state: "pending", stop_requested_at: nil)
                             .where(created_at: ..(now - UNSTARTED_RUN_THRESHOLD))
      undispatched = WorkflowRun.stuck_for_relay(now)
      waiting = SessionAdmission.unreleased.where(admitted_at: nil, stop_requested_at: nil)

      {
        unstarted_runs: unstarted.count,
        oldest_unstarted_seconds: age(unstarted.minimum(:created_at), now),
        undispatched_runs: undispatched.count,
        oldest_undispatched_seconds: age(undispatched.minimum(:created_at), now),
        queued_admissions: waiting.count,
        oldest_admission_wait_seconds: age(waiting.minimum(:created_at), now),
        pinned_reservations: SessionRuntimeOperation.pinning.count
      }
    end

    # What each number means when it is not zero, in the order an operator should
    # read them. `undispatched_runs` is listed before `unstarted_runs` because it
    # is the more specific diagnosis of the same symptom: the run never reached
    # Temporal at all, rather than reaching it and finding nobody home.
    def problems(stats)
      problems = []
      if stats[:undispatched_runs].positive?
        problems << "#{stats[:undispatched_runs]} run(s) never reached Temporal " \
                    "(oldest #{stats[:oldest_undispatched_seconds]}s)"
      end
      if stats[:unstarted_runs].positive?
        problems << "#{stats[:unstarted_runs]} run(s) unstarted for over " \
                    "#{UNSTARTED_RUN_THRESHOLD.inspect} (oldest #{stats[:oldest_unstarted_seconds]}s) — " \
                    "nothing is executing the queue"
      end
      if stats[:oldest_admission_wait_seconds] > ADMISSION_WAIT_THRESHOLD.to_i
        problems << "a session has waited #{stats[:oldest_admission_wait_seconds]}s for a slot"
      end
      if stats[:pinned_reservations].positive?
        problems << "#{stats[:pinned_reservations]} reservation(s) pinned by an unprovable runtime " \
                    "operation, holding capacity until an operator releases them"
      end
      problems
    end

    private

    def age(timestamp, now) = timestamp ? (now - timestamp).to_i : 0

    # One structured line every tick so the log pipeline has a series to draw, and
    # a Sentry event only when something is actually wrong — a watchdog that cries
    # every minute is one nobody reads.
    def report(stats)
      Rails.logger.info("[QueueHealth] #{stats.to_json}")
      found = problems(stats)
      return stats if found.empty?

      message = "Queue is not draining: #{found.join('; ')}"
      Rails.logger.error("[QueueHealth] #{message}")
      Sentry.capture_message(message, level: :error, extra: stats) if Sentry.initialized?
      stats
    end
  end
end
