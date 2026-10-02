# frozen_string_literal: true

module Billing
  # The one place this application talks to AWS Marketplace metering.
  #
  # An adapter for the same reason Billing::StripeClient is one: the tests below
  # it drive a fake of this rather than the vendor's classes. Outside an
  # installation bought through AWS Marketplace nothing here is ever reached.
  #
  # NOT Billing::AwsMarketplace: a module of that name would make every bare
  # `Aws` inside Billing::Meter::AwsMarketplace resolve to it rather than to the
  # SDK.
  class MarketplaceMeteringClient
    class Error < StandardError; end

    # An installation not bought through Marketplace has no product code, and
    # nothing here may be called.
    def configured?
      product_code.present?
    end

    # One closed hour of the whole installation, as one record.
    #
    # AWS accepts one record per dimension per hour per pod, and answers a second
    # for the same hour carrying a different quantity with
    # DuplicateRequestException. That refusal means "recorded", so it is answered
    # with :duplicate rather than an exception; otherwise the ledger would replay
    # an hour AWS already has until the window closed. An identical repeat is
    # idempotent and simply returns the original record id.
    def meter_usage(dimension:, quantity:, occurred_at:, allocations: {})
      api do
        begin
          params = {
            product_code: product_code,
            timestamp: occurred_at,
            usage_dimension: dimension,
            usage_quantity: quantity
          }
          list = allocation_list(allocations)
          params[:usage_allocations] = list if list.present?

          client.meter_usage(params).metering_record_id
        rescue ::Aws::MarketplaceMetering::Errors::DuplicateRequestException
          :duplicate
        end
      end
    end

    private

    def product_code
      settings.product_code
    end

    def settings
      ::Settings.aws_marketplace || Hashie::Mash.new
    end

    # Region and credentials come from the SDK's default chain, which reads the
    # token projected into the pod by its service account's IAM role.
    def client
      @client ||= ::Aws::MarketplaceMetering::Client.new
    end

    def allocation_list(allocations)
      allocations.map do |company_id, allocated|
        { allocated_usage_quantity: allocated, tags: [ { key: "company", value: company_id.to_s } ] }
      end
    end

    # One error class out of this adapter, so callers are not written against the
    # vendor's exception tree.
    def api
      raise Error, "no AWS Marketplace product code" unless configured?

      yield
    rescue ::Aws::MarketplaceMetering::Errors::ServiceError => e
      raise Error, "#{e.class.name.demodulize}: #{e.message}"
    end
  end
end
