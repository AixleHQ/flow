# frozen_string_literal: true

module Billing
  # AWS Marketplace, signed by the account that owns the SaaS listing.
  #
  # Separate from Billing::MarketplaceMeteringClient, and the difference is whose
  # credentials the call carries rather than which API it reaches: a SaaS listing
  # has no pod in the buyer's account, so the call is signed by the seller
  # account while this application runs in another.
  class MarketplaceSellerClient
    class Error < StandardError; end

    # The seller role could not be assumed. Nothing about the request was wrong.
    class CredentialsError < Error; end

    # Single use and short lived, so there is nothing to retry: the buyer has to
    # arrive again from Marketplace.
    class InvalidToken < Error; end

    # Checked here because this object is the one that knows which product the
    # installation sells, and a miss binds a stranger's subscription to a
    # workspace.
    class ForeignProduct < Error; end

    # What ResolveCustomer answers, without the vendor's types.
    #
    # `customer_identifier` is nil under Concurrent Agreements — AWS stopped
    # populating it — and is carried only so an old integration's question has an
    # answer. Nothing may key on it.
    Customer = Data.define(
      :license_arn, :aws_account_id, :product_code, :agreement_id, :customer_identifier
    )

    DEFAULT_REGION = "us-east-1"
    SESSION_NAME = "aixle-marketplace-saas"

    # Every installation but the one that sells the listing.
    def configured?
      seller_role_arn.present? && product_code.present?
    end

    def resolve_customer(registration_token:)
      api do
        answer = client.resolve_customer(registration_token: registration_token)

        unless answer.product_code == product_code
          raise ForeignProduct, "token resolves to product #{answer.product_code.inspect}, not ours"
        end

        Customer.new(
          license_arn: answer.license_arn,
          aws_account_id: answer.customer_aws_account_id,
          product_code: answer.product_code,
          agreement_id: answer.metadata&.agreement_id,
          customer_identifier: answer.customer_identifier.presence
        )
      end
    end

    private

    def settings
      ::Settings.aws_marketplace&.saas || Hashie::Mash.new
    end

    def product_code = settings.product_code
    def seller_role_arn = settings.seller_role_arn
    def region = settings.region.presence || DEFAULT_REGION

    # Explicit: the pod's region is whatever cluster it runs in, and the pod's
    # identity is the one account that must not sign this call.
    def client
      @client ||= ::Aws::MarketplaceMetering::Client.new(region: region, credentials: credentials)
    end

    def credentials
      @credentials ||= ::Aws::AssumeRoleCredentials.new(
        client: ::Aws::STS::Client.new(region: region),
        role_arn: seller_role_arn,
        role_session_name: SESSION_NAME
      )
    end

    # The STS rescue belongs here rather than around #credentials: the role is
    # assumed lazily, on the first call that needs it.
    def api
      raise Error, "no AWS Marketplace SaaS listing configured" unless configured?

      yield
    rescue ::Aws::MarketplaceMetering::Errors::InvalidTokenException,
           ::Aws::MarketplaceMetering::Errors::ExpiredTokenException => e
      raise InvalidToken, "#{e.class.name.demodulize}: #{e.message}"
    rescue ::Aws::STS::Errors::ServiceError => e
      raise CredentialsError, "cannot assume #{seller_role_arn}: #{e.class.name.demodulize}: #{e.message}"
    rescue ::Aws::MarketplaceMetering::Errors::ServiceError => e
      raise Error, "#{e.class.name.demodulize}: #{e.message}"
    end
  end
end
