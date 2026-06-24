# frozen_string_literal: true

module Activities
  module Outbox
    # Drains the transactional outbox: dispatches any trigger events left
    # "pending" past the grace window (producers that committed their domain write
    # but died before dispatching). Idempotent — TriggerDispatch dedup makes a
    # re-dispatch a no-op, so at-least-once delivery never double-launches.
    class RelayDrainActivity < ::Activities::Base
      def run(_input = nil)
        OutboxRelay.drain
      end
    end
  end
end
