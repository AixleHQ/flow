# frozen_string_literal: true

module Activities
  module Outbox
    # Drains both halves of the transactional outbox, in the order the work flows:
    #
    #   1. Trigger events left "pending" past the grace window — producers that
    #      committed their domain write but died before dispatching. Idempotent:
    #      TriggerDispatch dedup makes a re-dispatch a no-op.
    #   2. Runs that were created but whose Temporal execution was never confirmed
    #      started. Idempotent: the execution id is per-run and duplicates are
    #      rejected, with a rejected duplicate reported as success.
    #
    # Events first, because draining them is what creates runs — a run stranded by
    # the same outage is then swept in the same tick rather than the next one.
    class RelayDrainActivity < ::Activities::Base
      def run(_input = nil)
        events = OutboxRelay.drain
        runs = WorkflowRunRelay.drain
        { events: events, runs: runs }
      end
    end
  end
end
