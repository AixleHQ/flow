# frozen_string_literal: true

module Workflows
  # Drains the AWS Marketplace subscription queue (see app/temporal/schedules.yml).
  #
  # Retries, unlike the metering workflow beside it: nothing here bills anyone.
  # Recording is keyed on the event id and applying is a state machine that
  # refuses a move it has already made, so a repeated attempt changes nothing.
  class MarketplaceEventsWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.billing_drain_marketplace_events_activity, {},
        start_to_close_timeout: 120
      )
    end
  end
end
