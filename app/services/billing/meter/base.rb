# frozen_string_literal: true

module Billing
  module Meter
    # What a provider has to answer for one closed hour.
    #
    # `deliver` returns the provider's own identifier for the record it accepted,
    # or raises. A raise is what puts the report back in the replay window; a
    # return is what settles it, so an adapter must never swallow a rejection and
    # answer as though it had sent something.
    class Base
      Unavailable = Class.new(StandardError)

      def self.provider = name.demodulize.underscore

      def provider = self.class.provider

      # Whether this provider should be run at all on this installation. A
      # disabled one claims no ledger row, so an installation that does not sell
      # the listing does not accumulate an hourly row nobody can ever deliver.
      def enabled? = true

      # Which of the hour's companies are this provider's to bill, asked when
      # the row is claimed rather than delivered (CapacityMeter#claim).
      # Everyone, for an installation with one provider.
      def companies_billed(company_ids) = company_ids

      # @param report [CapacityMeterReport] the claimed row for this hour
      # @return [String] the provider's identifier for the accepted record
      def deliver(report)
        raise NotImplementedError, "#{self.class} must implement #deliver"
      end
    end
  end
end
