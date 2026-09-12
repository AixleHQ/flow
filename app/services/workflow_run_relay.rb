# frozen_string_literal: true

# The relay side of the transactional outbox for run DISPATCH. Sibling of
# OutboxRelay, which relays trigger events; this one relays the step after it.
#
# WHY BOTH EXIST: OutboxRelay guarantees that an event a producer committed
# eventually reaches WorkflowService.start. Nothing guaranteed the next hop.
# WorkflowService.start dials Temporal inline, and TemporalService.start_workflow
# does not raise on a failed RPC — it returns { ok: false, ... }. So a run created
# while Temporal was unreachable was committed, never executed, and looked exactly
# like one the worker had not picked up yet. There was no retry: the stale-run
# reaper only touches `running`/`paused` runs past four hours, and the admission
# reconciler does not look at runs at all. It sat in `pending` forever.
#
# Delivery is at-least-once and re-dispatch is idempotent: the Temporal execution
# id is per-run and duplicates are rejected, with a rejected duplicate reported as
# success (see TemporalWorkflowRegistry#start_workflow_execution).
class WorkflowRunRelay
  # Cap per sweep so one cron tick does a bounded amount of work; each run costs a
  # Temporal RPC. A backlog drains over successive minutely ticks.
  DEFAULT_LIMIT = 50

  class << self
    # Re-dispatch runs left undispatched past the grace window. Rows are claimed
    # under FOR UPDATE SKIP LOCKED in a short transaction so concurrent drainers
    # never grab the same run, and the lock is released before dispatching — the
    # Temporal call must not run while holding row locks.
    #
    # Returns { swept:, dispatched:, failed: } counts.
    def drain(limit: DEFAULT_LIMIT, now: Time.current)
      run_ids = claim_ids(limit: limit, now: now)
      dispatched = 0
      failed = 0

      run_ids.each do |id|
        run = WorkflowRun.find_by(id: id)
        next if run.nil?

        begin
          WorkflowService.dispatch!(run)
          dispatched += 1
          Rails.logger.info("[WorkflowRunRelay] run ##{id} dispatched on attempt #{run.relay_attempts}")
        rescue WorkflowService::DispatchFailed => e
          # Expected while the outage that stranded the run is still going. The
          # attempt counter is what eventually stops a poison run (RELAY_MAX_ATTEMPTS),
          # so a failure here is recorded and the sweep moves on.
          failed += 1
          Rails.logger.warn("[WorkflowRunRelay] run ##{id} still undispatched: #{e.message}")
        end
      end

      if run_ids.any?
        Rails.logger.warn("[WorkflowRunRelay] swept=#{run_ids.size} dispatched=#{dispatched} failed=#{failed}")
      end

      { swept: run_ids.size, dispatched: dispatched, failed: failed }
    end

    private

    def claim_ids(limit:, now:)
      WorkflowRun.transaction do
        WorkflowRun
          .stuck_for_relay(now)
          .limit(limit)
          .lock("FOR UPDATE SKIP LOCKED")
          .pluck(:id)
      end
    end
  end
end
