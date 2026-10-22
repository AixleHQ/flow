# frozen_string_literal: true

module Billing
  # AWS Marketplace, signed by the account that owns the SaaS listing.
  #
  # Separate from Billing::MarketplaceMeteringClient, and the difference is whose
  # credentials the call carries rather than which API it reaches. The container
  # product meters from inside the buyer's own AWS account, where the pod and the
  # subscription belong to the same account and the pod's own identity is the
  # right signer. A SaaS listing has no pod in the buyer's account: the call has
  # to be signed by the seller account while this application runs in another, so
  # it assumes a role there and refreshes it.
  #
  # That gap is a way to fail that has nothing to do with Marketplace. A role we
  # cannot assume and a token Marketplace refuses are different problems — the
  # first is ours and takes minutes, the second is the buyer's link having
  # expired — so they are different exceptions, and a caller that reports them
  # alike will send somebody to the wrong place.
  class MarketplaceSellerClient
    class Error < StandardError; end

    # The seller role could not be assumed. Nothing about the request was wrong.
    class CredentialsError < Error; end

    # Expired, already spent, or malformed. A registration token is single use
    # and short lived, so there is nothing to retry: the buyer has to arrive
    # again from Marketplace.
    class InvalidToken < Error; end

    # A token that resolves to a different product. Checked here rather than
    # left to a caller because this object is the one that knows which product
    # the installation sells, and a miss is the kind of thing that binds a
    # stranger's subscription to a workspace.
    class ForeignProduct < Error; end

    # What ResolveCustomer answers, without the vendor's types.
    #
    # `license_arn` is the key: one per agreement, and under Concurrent
    # Agreements one AWS account may hold several at once. `customer_identifier`
    # is nil on such a product — AWS stopped populating it — and is carried only
    # so that a support question about an old integration has an answer.
    Customer = Data.define(
      :license_arn, :aws_account_id, :product_code, :agreement_id, :customer_identifier
    )

    DEFAULT_REGION = "us-east-1"
    SESSION_NAME = "aixle-marketplace-saas"

    # Nothing here may be called on an installation that does not sell the SaaS
    # listing, which is every installation but ours.
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

    # Explicit, not the SDK's default chain. The pod's own region is whatever
    # cluster it runs in and the listing's is not negotiable; and the pod's own
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

    # One error tree out of this adapter, so callers are not written against the
    # vendor's. The STS rescue has to be here rather than around #credentials:
    # the role is assumed lazily, on the first call that needs it.
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
