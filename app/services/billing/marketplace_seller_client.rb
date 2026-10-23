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

    # BatchMeterUsage takes at most 25 usage records per call.
    BATCH_SIZE = 25

    # What DescribeAgreement answers, of which only the status is load-bearing.
    # `status` is a free string in the SDK model, not an enum, so it is compared
    # rather than matched.
    Agreement = Data.define(:id, :status, :offer_id, :acceptor_account_id) do
      # The one value that means AWS will accept metering. Everything else --
      # cancelled, expired, superseded, or a spelling we have not seen -- leaves
      # the licence where it was, which bills nobody.
      def live? = status == "ACTIVE"
    end

    # What AWS answers per record. `DuplicateRecord` means the hour is already
    # held, which is a success for a replay rather than a failure to retry.
    SUCCESS = "Success"
    DUPLICATE = "DuplicateRecord"

    # One licence's usage for one hour, as this adapter takes it.
    Usage = Data.define(:license_arn, :dimension, :quantity, :occurred_at)

    # What came back for it, without the vendor's types.
    Outcome = Data.define(:license_arn, :status, :metering_record_id) do
      def accepted? = status == SUCCESS || status == DUPLICATE
      def duplicate? = status == DUPLICATE
    end

    # Every installation but the one that sells the listing.
    def configured?
      seller_role_arn.present? && product_code.present?
    end

    def resolve_customer(registration_token:)
      # The SDK answers a nil required parameter with ArgumentError, which is
      # outside the error tree every caller rescues -- so an arrival with no
      # token at all became a 500 rather than the same refusal a stale one
      # gets. The endpoint is reachable without credentials by design, so that
      # is anyone's to trigger.
      raise InvalidToken, "no registration token" if registration_token.blank?

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

    # Asked at registration, because the event that would say the same thing
    # races the buyer's arrival here and loses about half the time. Answers nil
    # rather than raising when the agreement cannot be read: a licence that stays
    # `pending` bills nobody, which is the safe direction to fail in.
    def describe_agreement(agreement_id:)
      return nil if agreement_id.blank?

      api do
        answer = agreement_client.describe_agreement(agreement_id: agreement_id)

        Agreement.new(
          id: answer.agreement_id,
          status: answer.status,
          offer_id: answer.proposal_summary&.offer_id,
          acceptor_account_id: answer.acceptor&.account_id
        )
      end
    rescue Error
      nil
    end

    # Up to 25 records a call, as AWS counts them. Returns one Outcome per record
    # — including the ones AWS could not process, which come back under their own
    # key and would otherwise be silently dropped from a count of what landed.
    def batch_meter_usage(usages)
      return [] if usages.empty?

      api do
        usages.each_slice(BATCH_SIZE).flat_map do |slice|
          answer = client.batch_meter_usage(usage_records: slice.map { |usage| usage_record(usage) })

          outcomes(answer) + unprocessed(answer)
        end
      end
    end

    private

    # No product code: for a product on Concurrent Agreements AWS takes the
    # licence instead and refuses the other keying. Sending both would not be
    # refused — the one-record-per-hour limit counts each keying separately — it
    # would bill the hour twice.
    def usage_record(usage)
      {
        timestamp: usage.occurred_at,
        dimension: usage.dimension,
        quantity: usage.quantity,
        license_arn: usage.license_arn
      }
    end

    def outcomes(answer)
      Array(answer.results).map do |result|
        Outcome.new(
          license_arn: result.usage_record&.license_arn,
          status: result.status,
          metering_record_id: result.metering_record_id
        )
      end
    end

    def unprocessed(answer)
      Array(answer.unprocessed_records).map do |record|
        Outcome.new(license_arn: record.license_arn, status: "Unprocessed", metering_record_id: nil)
      end
    end

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

    # A different service from the metering one, and so a different client, but
    # the same assumed seller identity: an agreement is readable only by the
    # account that proposed it.
    def agreement_client
      @agreement_client ||= ::Aws::MarketplaceAgreement::Client.new(region: region, credentials: credentials)
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
    rescue ::Aws::MarketplaceMetering::Errors::ServiceError,
           ::Aws::MarketplaceAgreement::Errors::ServiceError => e
      raise Error, "#{e.class.name.demodulize}: #{e.message}"
    end
  end
end
