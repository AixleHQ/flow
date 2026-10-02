# frozen_string_literal: true

module Billing
  module Meter
    # One installation is one AWS Marketplace agreement, so this sends the
    # installation total as a single record, with the per-company split carried
    # as usage allocations for the buyer's own cost reporting.
    #
    # THE ONE PLACE A FRACTION IS LOST. `MeterUsage` takes `UsageQuantity` as an
    # Integer, so the exact figure is rounded here and nowhere else.
    #
    # DOWN, never up. The rounding direction is the one thing about it a customer
    # would notice, and charging for a minute that was not given is worse than
    # giving away one that was. In minutes rather than hours, so the most that
    # can be lost is under a queue_minute an hour.
    #
    # ONE ATTEMPT, NOT A RETRY LOOP. AWS counts its once-per-hour budget per
    # caller, so a retry landing on another replica would find an unused budget
    # and bill the customer twice rather than meeting DuplicateRequestException.
    # Recovery is the next run replaying the ledger, which is why this raises on
    # failure instead of trying again, and why a duplicate is answered as
    # recorded rather than as an error.
    class AwsMarketplace < Base
      # Must match the dimension's API identifier in the listing character for
      # character. The listing spells it with an underscore because the portal
      # accepts letters, digits and underscores and refuses the hyphen this was
      # written with until 29 September 2026.
      DIMENSION = "queue_minute"

      def initialize(client: ::Billing::MarketplaceMeteringClient.new)
        super()
        @client = client
      end

      attr_reader :client

      def deliver(report)
        result = client.meter_usage(
          dimension: DIMENSION,
          quantity: quantity_for(report),
          occurred_at: report.period_start,
          allocations: allocations_for(report)
        )

        return result unless result == :duplicate

        # AWS already holds this hour. Answering with an identifier settles the
        # ledger row, which is the truth: the record exists, we simply are not
        # the ones who were told its id.
        "aws:already-recorded:#{report.period_start.utc.iso8601}"
      end

      # The integer AWS is given. Allocations have to sum to it exactly or the
      # call is refused, so the largest-remainder split below is not cosmetic.
      def quantity_for(report)
        report.quantity_minutes.floor
      end

      # Each company's share, rounded so the parts still add up to the whole.
      def allocations_for(report)
        exact = report.breakdown_minutes
        total = quantity_for(report)
        return {} if total.zero? || exact.empty?

        floors = exact.transform_values { |minutes| minutes.floor }
        remainder = total - floors.values.sum
        ranked = exact.sort_by { |company_id, minutes| [ -(minutes - minutes.floor), company_id.to_s ] }
        ranked.first(remainder.clamp(0, ranked.size)).each { |company_id, _| floors[company_id] += 1 }
        floors
      end
    end
  end
end
