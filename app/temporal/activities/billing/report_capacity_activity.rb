# frozen_string_literal: true

module Activities
  module Billing
    # Measures the hour that has just closed and sends everything still unsent
    # inside the replay window.
    #
    # Runs with a single attempt on purpose (see the workflow): a Temporal retry
    # landing on a different pod would bill an AWS Marketplace customer twice for
    # the same hour. Recovery is the next hourly run replaying the ledger.
    class ReportCapacityActivity < ::Activities::Base
      def run(_input = nil)
        ::Billing::CapacityMeter.new.call
      end
    end
  end
end
