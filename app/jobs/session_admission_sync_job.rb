# frozen_string_literal: true

# Applies a changed `SESSION_CONCURRENCY_LIMIT` on its own, so the deployment's
# ceiling takes effect from a ConfigMap edit and nothing else.
#
# WHY IT IS NOT A RAKE TASK: `session_admission:sync` assumes a shell in a
# production pod, and a deployed installation has nobody with one. It is worse
# than inconvenient — after activation the admin page offers Pause and Resume and
# no way to apply a new ceiling at all, so the value simply never took.
#
# WHY IT IS NOT IN THE TEMPORAL WORKER: same reason as QueueHealthCheckJob. The
# Solid Queue supervisor (`jobs`) survives a worker outage, and a queue that
# cannot be resized while the worker is down is a queue nobody can rescue.
#
# It only ever moves the number. Enabling admission is a cutover with a drain
# gate behind it and stays a deliberate act; a pause stays somebody's decision.
class SessionAdmissionSyncJob < ApplicationJob
  queue_as :default

  # Never retry: the next tick is a minute away and reads the configuration
  # afresh, so a retry could only re-apply a world that has already moved on.
  discard_on StandardError do |_job, error|
    Rails.logger.error("[SessionAdmissionSync] failed: #{error.class}: #{error.message}")
    Sentry.capture_exception(error) if Sentry.initialized?
  end

  def perform
    result = SessionAdmissionPolicy.reconcile_installation_limit!

    case result[:state]
    when :applied
      Rails.logger.info("[SessionAdmissionSync] #{result[:detail]}")
      # A raised ceiling is capacity that exists now; whoever is waiting for it
      # should not wait for the next reconciliation pass as well.
      SessionAdmissionService.drain!
    when :refused, :invalid
      # Both are operator errors in deployment configuration, and both leave the
      # last good value in place. Reported rather than raised — this runs every
      # minute, and the interesting event is the misconfiguration, not the tick.
      Rails.logger.error("[SessionAdmissionSync] #{result[:detail]}")
      Sentry.capture_message("Session admission ceiling not applied: #{result[:detail]}",
        level: :error) if Sentry.initialized?
    end

    result
  end
end
