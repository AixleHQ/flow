# frozen_string_literal: true

module Billing
  # The one place this application talks to AWS Marketplace metering.
  #
  # An adapter for the same reason Billing::StripeClient is one: the tests below
  # it drive a fake of this rather than the vendor's classes, and "is this
  # installation entitled to meter at all" is asked once instead of at every call
  # site. Outside an installation bought through AWS Marketplace nothing here is
  # ever reached.
  #
  # NOT Billing::AwsMarketplace: a module of that name would make every bare
  # `Aws` inside Billing::Meter::AwsMarketplace resolve to it rather than to the
  # SDK.
  class MarketplaceMeteringClient
    class Error < StandardError; end

    # Which product the record is billed against. It reaches the pod as an
    # environment variable, put there by the installation from the code the
    # buyer's subscription issued; an installation that was not bought through
    # Marketplace has none, and nothing here may be called.
    def configured? = product_code.present?

    # One closed hour of the whole installation, as one record.
    #
    # AWS accepts one record per product per account per hour and answers a
    # second with DuplicateRequestException. That refusal means "recorded", not
    # "failed", so it is answered with :duplicate rather than an exception —
    # otherwise the ledger would replay an hour AWS already has until the window
    # closed.
    #
    # `allocations` is the per-company split, which AWS carries for the buyer's
    # own cost reporting and nothing else. Its parts must add up to `quantity`
    # exactly or the whole call is refused, which is why the caller rounds them
    # together rather than one at a time.
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

    def product_code = settings.product_code

    def settings = ::Settings.aws_marketplace || Hashie::Mash.new

    # Region and credentials come from the environment: the pod runs under a
    # service account annotated with an IAM role, and the SDK's default chain
    # reads the token that projects into it. Nothing is configured here, so
    # nothing here can be configured wrongly.
    def client = @client ||= ::Aws::MarketplaceMetering::Client.new

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
