# frozen_string_literal: true

module Billing
  # Who pays for one company, and what follows from that.
  #
  # `Deployment` still answers for the installation and is the fallback for a
  # company with no payer of its own, so self-hosted and AWS Marketplace
  # container installations answer as they always did.
  class Payer
    def self.for(company) = new(company)

    def initialize(company)
      @company = company
    end

    attr_reader :company

    def provider = company&.billing_provider || Company::BILLING_PROVIDER_NONE

    def none? = provider == Company::BILLING_PROVIDER_NONE
    def stripe? = provider == Company::BILLING_PROVIDER_STRIPE

    # Who this company's hours are SENT to, and whose banner and Billing panel
    # it sees: the two meters, the Marketplace banner and the AWS panel read
    # this. Deliberately not the same question as #subscribed_through_aws?.
    # An ended licence leaves the column at `aws` until a card moves it back,
    # and in that interval the screens still say the AWS subscription has
    # ended and point at Billing, where a card is offered -- while nothing
    # refuses the card, which is the other predicate's job.
    def aws_marketplace? = provider == Company::BILLING_PROVIDER_AWS_MARKETPLACE

    # Whether a card would be a SECOND bill for capacity somebody is already
    # charged for. Read by every screen and refusal that turns a card away.
    # Not #aws_marketplace?: see above, and a pending licence is live but
    # metered by nobody.
    def subscribed_through_aws?
      return false if company.nil?

      company.marketplace_license.present?
    end

    # Not `!none?`: a company that has never paid is still billable — its minutes
    # go on the ledger row and the provider reports it as unbilled — so reading
    # the column here would drop it out of the metered quantity.
    def bills?
      return false if company.nil?

      Deployment.saas? && !company.managed_by_aixle?
    end

    # Installation-wide until a Marketplace customer can sit beside a Stripe one.
    def requires_bound? = Deployment.requires_bounded_companies?
    def minimum_workers = Deployment.minimum_workers
  end
end
