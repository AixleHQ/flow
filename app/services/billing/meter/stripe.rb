# frozen_string_literal: true

module Billing
  module Meter
    # Stripe bills each organisation separately, so this is the one provider that
    # consumes the per-company breakdown rather than the installation total. It
    # accepts a fractional value, so it is sent the exact figure — no rounding
    # happens anywhere on this path.
    #
    # One meter event per company per hour, carrying the exact figure.
    #
    # The event's `identifier` is the company and the hour, which is what makes
    # the ledger's replay safe: an hour that failed halfway is resent in full, and
    # Stripe refuses the parts it has already recorded rather than billing them
    # twice.
    #
    # A company with no Stripe customer is skipped and logged rather than raising.
    # It should not happen — a company is only billable once somebody has paid —
    # but one company missing its id must not stop the hour for everybody else.
    class Stripe < Base
      UNIT = "queue-minute"

      def initialize(client: ::Billing::StripeClient.new)
        super()
        @client = client
      end

      attr_reader :client

      def deliver(report)
        customers = customer_ids_for(report)
        sent = 0
        already = 0

        report.breakdown_minutes.each do |company_id, minutes|
          customer_id = customers[company_id.to_i]
          next skip(company_id, minutes, report) if customer_id.blank?

          result = client.send_meter_event(
            customer_id: customer_id,
            minutes: minutes,
            occurred_at: report.period_start,
            identifier: ::Billing::StripeClient.idempotency_key("capacity", company_id, report.period_start.to_i)
          )
          result == :duplicate ? already += 1 : sent += 1
        end

        # Carried on the ledger row, so a replayed hour is readable afterwards as
        # what it was rather than as a second charge.
        "stripe:#{report.period_start.utc.iso8601}:sent=#{sent}:already=#{already}"
      end

      private

      def customer_ids_for(report)
        ::Company.where(id: report.breakdown_minutes.keys).pluck(:id, :stripe_customer_id).to_h
      end

      def skip(company_id, minutes, report)
        Rails.logger.error(
          "[Billing::Meter::Stripe] company #{company_id} has no Stripe customer; " \
          "#{minutes.to_s('F')} #{UNIT}(s) at #{report.period_start.utc.iso8601} were not billed"
        )
      end
    end
  end
end
