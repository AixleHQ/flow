# frozen_string_literal: true

module Billing
  module Meter
    # The hosted product's AWS Marketplace customers.
    #
    # Built from Meter::Stripe rather than from Meter::AwsMarketplace, and the
    # reason is who the invoice goes to. The container product sends one record
    # for a whole installation and splits companies into usage allocations, which
    # are detail inside one buyer's bill; here every licence is a separate
    # customer with a separate bill, exactly as every Stripe customer is.
    #
    # So there is no remainder to redistribute either: the container adapter's
    # largest-remainder split exists only because one call carries one quantity,
    # and each licence's minutes are simply floored.
    class AwsMarketplaceSaas < Base
      # Immutable once the listing is published, and must match the dimension's
      # API identifier character for character. Deliberately NOT the container
      # product's `queue_minute`: the two products bill for different things, and
      # that one is published and cannot move.
      DIMENSION = "worker_minute"

      def initialize(client: ::Billing::MarketplaceSellerClient.new)
        super()
        @client = client
      end

      attr_reader :client

      def enabled? = client.configured?

      def deliver(report)
        usages, unbillable = usages_for(report)
        outcomes = client.batch_meter_usage(usages)

        refused = outcomes.reject(&:accepted?)
        raise ::Billing::MarketplaceSellerClient::Error, refusal(refused) if refused.any?

        summary(report, outcomes, unbillable)
      end

      private

      def usages_for(report)
        licenses = licenses_for(report)
        unbillable = 0

        usages = report.breakdown_minutes.filter_map do |company_id, minutes|
          license_arn = licenses[company_id.to_i]
          # `next` without a value, deliberately: inside filter_map a `next x`
          # keeps x, so the counting idiom Meter::Stripe uses inside `each`
          # would put the running total into the records.
          if license_arn.blank?
            unbillable += 1
            next
          end

          quantity = minutes.floor
          next if quantity.zero?

          ::Billing::MarketplaceSellerClient::Usage.new(
            license_arn: license_arn, dimension: DIMENSION,
            quantity: quantity, occurred_at: report.period_start
          )
        end

        [ usages, unbillable ]
      end

      # Only companies AWS will accept usage for: the licence has to be live, and
      # the company has to be one AWS bills. A Stripe company on the same
      # installation is not ours to report and is counted, not sent.
      def licenses_for(report)
        ::MarketplaceLicense
          .where(company_id: report.breakdown_minutes.keys, subscription_state: %w[active ending])
          .joins(:company)
          .where(companies: { billing_provider: ::Company::BILLING_PROVIDER_AWS_MARKETPLACE })
          .pluck(:company_id, :license_arn)
          .to_h
      end

      # Carried on the ledger row so an hour reads afterwards as what it was: a
      # replay rather than a second charge, and companies nobody bills rather
      # than companies we failed to bill.
      def summary(report, outcomes, unbillable)
        already = outcomes.count(&:duplicate?)

        "aws_saas:#{report.period_start.utc.iso8601}:" \
          "sent=#{outcomes.size - already}:already=#{already}:unbilled=#{unbillable}"
      end

      def refusal(refused)
        refused.map { |outcome| "#{outcome.license_arn}: #{outcome.status}" }.join("; ")
      end
    end
  end
end
