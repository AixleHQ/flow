# frozen_string_literal: true

module Billing
  module Meter
    # Stripe bills each organisation separately, so this is the one provider that
    # consumes the per-company breakdown rather than the installation total. It
    # accepts a fractional value, so it is sent the exact figure — no rounding
    # happens anywhere on this path.
    #
    # NOT IMPLEMENTED YET. Stripe is not wired up — there is no account, no
    # customer mapping and no meter. What exists is the seam and the shape of the
    # call, so the hourly loop can be run and read before any of that lands. The
    # log line carries exactly what a real send would carry.
    class Stripe < Base
      UNIT = "queue-minute"

      def deliver(report)
        report.breakdown_minutes.each do |company_id, minutes|
          Rails.logger.info(
            "[Billing::Meter::Stripe] would record #{minutes.to_s('F')} #{UNIT}(s) for company #{company_id} " \
            "at #{report.period_start.utc.iso8601}"
          )
        end

        "stripe-pending-#{report.period_start.utc.iso8601}"
      end
    end
  end
end
