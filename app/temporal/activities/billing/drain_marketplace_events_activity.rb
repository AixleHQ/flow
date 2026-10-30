# frozen_string_literal: true

module Activities
  module Billing
    # Reads the subscription events AWS delivered and applies what it can.
    #
    # Draining and applying are one activity but two steps, and the order
    # matters: everything on the queue is recorded first, so a failure while
    # applying never costs an event. What cannot be applied yet -- an agreement
    # whose buyer has not reached the fulfilment page -- stays recorded and is
    # retried by the next run.
    class DrainMarketplaceEventsActivity < ::Activities::Base
      def run(_input = nil)
        queue = ::Billing::MarketplaceEventsQueue.new
        return { read: 0, applied: 0 } unless queue.configured?

        events = ::Billing::MarketplaceEvents.new
        read = queue.each_message { |envelope| events.record(envelope) }

        { read: read, applied: events.apply_pending }
      end
    end
  end
end
