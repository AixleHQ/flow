# frozen_string_literal: true

module Billing
  # Who pays for one company, and what follows from that.
  #
  # The axis is older than the column it reads. `Deployment.saas? &&
  # !managed_by_aixle?` was spelled in four places, no two of them the same, and
  # each meant one thing: we host this installation, *and* this particular
  # company is one somebody is charged for. This is that sentence with a name.
  #
  # `Deployment` keeps answering for the installation, and is what a company
  # with no payer of its own falls back to, so a self-hosted installation and an
  # AWS Marketplace container installation answer exactly as they did.
  class Payer
    def self.for(company) = new(company)

    def initialize(company)
      @company = company
    end

    attr_reader :company

    def provider = company&.billing_provider || Company::BILLING_PROVIDER_NONE

    def none? = provider == Company::BILLING_PROVIDER_NONE
    def stripe? = provider == Company::BILLING_PROVIDER_STRIPE
    def aws_marketplace? = provider == Company::BILLING_PROVIDER_AWS_MARKETPLACE

    # Whether anyone is invoiced for this company's capacity.
    #
    # Deliberately not `!none?`. Being billable and having a payer attached are
    # different facts: a company that has never paid is still billable — its
    # minutes go on the ledger row and the provider reports it as unbilled —
    # and reading the column here would silently drop those companies out of
    # the metered quantity.
    def bills?
      return false if company.nil?

      Deployment.saas? && !company.managed_by_aixle?
    end

    # Installation-wide answers today, asked of a company because that is what
    # they are about. They stop being installation-wide the moment a Marketplace
    # customer can sit beside a Stripe one; routing them through here now makes
    # that a change to one object rather than to ten call sites.
    def requires_bound? = Deployment.requires_bounded_companies?
    def minimum_workers = Deployment.minimum_workers
  end
end
