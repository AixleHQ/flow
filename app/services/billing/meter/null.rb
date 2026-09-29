# frozen_string_literal: true

module Billing
  module Meter
    # A self-hosted installation bills nobody, so there is nothing to send. The
    # hour is still measured and recorded: the number is what an operator reads
    # to size their cluster, and it is what a later switch to a paid mode would
    # otherwise have no history for.
    class Null < Base
      def self.provider = "none"

      def deliver(report)
        "local-#{report.period_start.utc.iso8601}"
      end
    end
  end
end
