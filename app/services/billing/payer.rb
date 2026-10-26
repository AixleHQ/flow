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

    # Who this company's hours are SENT to. Read by the two meters, and by
    # nothing that decides what a screen offers.
    def aws_marketplace? = provider == Company::BILLING_PROVIDER_AWS_MARKETPLACE

    # Whether a card would be a SECOND bill for capacity somebody is already
    # being charged for. Read by every screen and refusal that turns a card
    # away, and by the Stripe webhook when it decides whether an event is about
    # a subscription this workspace has left behind.
    #
    # A different question from #aws_marketplace?, and they disagree exactly
    # where it matters. A licence that has ended leaves the column saying `aws`
    # until a card moves it back, and nothing is subscribed through AWS any
    # more -- so a card must be offered. A licence AWS has not confirmed yet is
    # live, and is not metered: the column says `aws` and no hour is sent.
    # Asking one of these when the other was meant is how a workspace ends up
    # offered a second payer, or billed by neither.
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
