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
    # can be lost is under a queue-minute an hour.
    #
    # NOT IMPLEMENTED YET. The real call is `MeterUsage` from inside the buyer's
    # cluster, signed with EKS IRSA or an ECS task role, and it carries
    # constraints this stub does not yet honour — one record per dimension per
    # hour PER POD, so a retry that lands on another replica bills twice; a
    # six-hour ceiling on backfill; a region resolved at runtime. The activity is
    # already built around those (single attempt, replay from the ledger), which
    # is why this is safe to leave as a log line for now.
    class AwsMarketplace < Base
      DIMENSION = "queue-minute"

      def deliver(report)
        Rails.logger.info(
          "[Billing::Meter::AwsMarketplace] would meter #{quantity_for(report)} #{DIMENSION}(s) " \
          "at #{report.period_start.utc.iso8601} (exact #{report.quantity_minutes.to_s('F')}), " \
          "allocated as #{allocations_for(report).inspect}"
        )

        "aws-pending-#{report.period_start.utc.iso8601}"
      end

      # The integer AWS is given. Allocations have to sum to it exactly or the
      # call is refused, so the largest-remainder split below is not cosmetic.
      def quantity_for(report) = report.quantity_minutes.floor

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
