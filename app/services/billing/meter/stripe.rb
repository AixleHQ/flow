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
    # A company with no Stripe customer is skipped, and that is ordinary rather
    # than exceptional: an installation bills some companies and not others. Our
    # own is `active` because we say so, not because anyone pays us, and it will
    # never have a customer. Counted on the ledger row instead of logged, because
    # a log line per company per hour for a permanent condition is noise that
    # buries the hour something actually goes wrong.
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
        unbilled = 0

        report.breakdown_minutes.each do |company_id, minutes|
          # Absent from the hash means AWS bills it, which is not the same as
          # nobody billing it: counting it here would read as a company we fail
          # to charge.
          next unless customers.key?(company_id.to_i)

          customer_id = customers[company_id.to_i]
          next unbilled += 1 if customer_id.blank?

          result = client.send_meter_event(
            customer_id: customer_id,
            minutes: minutes,
            occurred_at: report.period_start,
            identifier: ::Billing::StripeClient.idempotency_key("capacity", company_id, report.period_start.to_i)
          )
          result == :duplicate ? already += 1 : sent += 1
        end

        # Carried on the ledger row, so an hour is readable afterwards as what it
        # was — a replay rather than a second charge, and companies nobody bills
        # rather than companies we failed to bill.
        "stripe:#{report.period_start.utc.iso8601}:sent=#{sent}:already=#{already}:unbilled=#{unbilled}"
      end

      # Everyone AWS does not bill. A company with no customer yet is still this
      # provider's: its minutes go on the row as unbilled, which says "nobody
      # has paid for this yet" rather than "somebody else did".
      def companies_billed(company_ids)
        ::Company.where(id: company_ids)
                 .where.not(billing_provider: ::Company::BILLING_PROVIDER_AWS_MARKETPLACE)
                 .pluck(:id)
      end

      private

      # Narrowed rather than re-keyed: the rule is still "has a Stripe customer",
      # with AWS's own companies taken out. Left in, one would be counted as
      # unbilled — which reads as "nobody pays for this" when AWS does.
      def customer_ids_for(report)
        ::Company
          .where(id: report.breakdown_minutes.keys)
          .where.not(billing_provider: ::Company::BILLING_PROVIDER_AWS_MARKETPLACE)
          .pluck(:id, :stripe_customer_id)
          .to_h
      end
    end
  end
end
