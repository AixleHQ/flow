# frozen_string_literal: true

# The relay side of the transactional outbox. Internal producers record trigger
# events as relay_state "pending" inside the same transaction as their domain
# write and then dispatch them inline. If a process dies after the commit but
# before/while dispatching, the event is left "pending"; this relay — driven by a
# Temporal cron (see OutboxRelayWorkflow) — sweeps anything stuck past the grace
# window and dispatches it. Delivery is at-least-once; TriggerEngine.dispatch_pending
# is idempotent (TriggerDispatch dedup), so a re-dispatch never double-launches.
class OutboxRelay
  # Cap per sweep so one cron tick does a bounded amount of work. Kept small so a
  # full drain (each event may make a Temporal RPC) finishes well inside the
  # activity timeout; a backlog drains over successive minutely ticks.
  DEFAULT_LIMIT = 50

  class << self
    # Sweep stuck events and dispatch each. Rows are claimed under FOR UPDATE SKIP
    # LOCKED in a short transaction (so concurrent drainers never grab the same
    # row) and the lock is released before dispatching — the external
    # WorkflowService.start call must not run while holding row locks.
    # Returns { swept:, dispatched: } counts.
    def drain(limit: DEFAULT_LIMIT, now: Time.current)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      event_ids = claim_ids(limit: limit, now: now)
      dispatched = 0

      event_ids.each do |id|
        event = TriggerEvent.find_by(id: id)
        next if event.nil?

        runs = TriggerEngine.dispatch_pending(event)
        dispatched += 1 if event.reload.relay_state == "dispatched"
        Rails.logger.info("[OutboxRelay] event ##{id} → #{event.relay_state} (#{runs.size} run(s))")
      end

      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)
      # Warn if a sweep approaches the grace window: that means in-flight inline
      # dispatches risk being re-swept and the limit/cadence needs tuning.
      level = elapsed > TriggerEvent::RELAY_GRACE.to_i * 0.5 ? :warn : :info
      Rails.logger.send(level, "[OutboxRelay] swept=#{event_ids.size} dispatched=#{dispatched} in #{elapsed}s")

      { swept: event_ids.size, dispatched: dispatched, elapsed: elapsed }
    end

    private

    def claim_ids(limit:, now:)
      TriggerEvent.transaction do
        TriggerEvent
          .stuck_for_relay(now)
          .limit(limit)
          .lock("FOR UPDATE SKIP LOCKED")
          .pluck(:id)
      end
    end
  end
end
