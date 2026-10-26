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

      # Only companies the column says AWS bills. A licence that is not live yet
      # still belongs here: the hour is this provider's and is counted unbilled,
      # rather than falling to Stripe, which has no customer for it either.
      def companies_billed(company_ids)
        ::Company.where(id: company_ids, billing_provider: ::Company::BILLING_PROVIDER_AWS_MARKETPLACE).pluck(:id)
      end

      def deliver(report)
        usages, unbillable = usages_for(report)
        outcomes = client.batch_meter_usage(usages)

        # Written BEFORE anything is raised, and merged rather than replaced.
        # AWS answers each record separately, so one refusal among twenty does
        # not mean the other nineteen were not billed -- and dropping their
        # receipts to raise on the one would leave the retry unable to tell
        # which. The receipt is the only evidence of acceptance that is not our
        # own word; it is also what stops the retry sending them again.
        report.update!(receipts: report.receipts.merge(receipts(outcomes)))

        retryable = outcomes.select(&:retryable?)
        raise ::Billing::MarketplaceSellerClient::Error, refusal(retryable) if retryable.any?

        summary(report, outcomes, unbillable)
      end

      private

      def usages_for(report)
        licenses = licenses_for(report)
        unbillable = 0

        usages = report.breakdown_minutes.filter_map do |company_id, minutes|
          license = licenses[company_id.to_i]
          # Already receipted on an earlier attempt at this same hour. Sending
          # it again would be answered `Success` with the id AWS already
          # issued, which reads afterwards as a second charge that never
          # happened.
          next if license && report.receipts[license.first].present?
          # `next` without a value, deliberately: inside filter_map a `next x`
          # keeps x, so the counting idiom Meter::Stripe uses inside `each`
          # would put the running total into the records.
          if license.nil?
            unbillable += 1
            next
          end

          quantity = minutes.floor
          next if quantity.zero?

          ::Billing::MarketplaceSellerClient::Usage.new(
            license_arn: license.first, customer_aws_account_id: license.last,
            dimension: DIMENSION, quantity: quantity, occurred_at: report.period_start
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
          .pluck(:company_id, :license_arn, :customer_aws_account_id)
          .to_h { |company_id, arn, account| [ company_id, [ arn, account ] ] }
      end

      # Licence -> what AWS called the record. A duplicate carries no id of its
      # own, so it is marked as the duplicate it is rather than left looking
      # like a record that went missing.
      def receipts(outcomes)
        outcomes.to_h { |o| [ o.license_arn, o.metering_record_id || (o.duplicate? ? "duplicate" : nil) ] }
      end

      # Carried on the ledger row so an hour reads afterwards as what it was: a
      # replay rather than a second charge, and companies nobody bills rather
      # than companies we failed to bill.
      # `disputed` rather than `already`: a duplicate is an hour AWS refused
      # because it had already been told a different number for it, so it is
      # unbilled and somebody has to look. Counting it as sent was what hid
      # that.
      def summary(report, outcomes, unbillable)
        disputed = outcomes.count(&:duplicate?)
        line = "aws_saas:#{report.period_start.utc.iso8601}:" \
               "sent=#{outcomes.count(&:accepted?)}:unbilled=#{unbillable}"
        return line if disputed.zero?

        "#{line}:disputed=#{disputed}"
      end

      def refusal(refused)
        refused.map { |outcome| "#{outcome.license_arn}: #{outcome.status}" }.join("; ")
      end
    end
  end
end
