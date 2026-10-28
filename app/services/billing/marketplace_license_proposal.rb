# frozen_string_literal: true

module Billing
  # A subscription bought in AWS asking to be applied to a workspace that
  # already exists, and an administrator of that workspace deciding.
  #
  # WHY A PERSON DECIDES. A buyer whose email domain already has a workspace
  # cannot create a second one, so without this they pay and the licence stays
  # bound to nothing. Attaching it for them is the move the design refuses:
  # it moves that workspace onto AWS billing silently, and it would let anyone
  # holding an address at the domain re-bill somebody else's workspace through
  # their own AWS account — and then stop it by unsubscribing.
  #
  # TWO THINGS STOP THAT. The workspace is never chosen: it is whichever one
  # holds the proposer's own email domain. And the proposer's address is one
  # they have proved by opening a link sent to it, not one they typed, so a
  # proposal cannot be raised against a domain the proposer has no mailbox at.
  # Past both, an administrator of that workspace still has to say yes.
  class MarketplaceLicenseProposal
    Refused = Class.new(StandardError)

    NOT_PROPOSABLE = "That subscription is already set up, or has ended."
    NOT_PENDING = "That request has already been answered."
    NOT_CONFIRMED = "AWS has not confirmed that subscription yet. Try again in a few minutes."
    DOMAIN_FREE = "There is no workspace at that domain to apply it to."
    ALREADY_BILLED = "That workspace already has an AWS Marketplace subscription."

    # The workspace is derived from the proved address and never passed in, so
    # there is no parameter here through which to aim a proposal somewhere else.
    def self.raise!(license:, email:)
      company = Company.find_by(email_domain: email.to_s.split("@").last.to_s.downcase)
      raise Refused, DOMAIN_FREE if company.nil?

      new(license).send(:propose!, company: company, email: email)
    end

    def self.pending_for(company) = MarketplaceLicense.proposed_to(company).proposable.first

    def initialize(license)
      @license = license
    end

    attr_reader :license

    def company = license.proposed_company

    # Only a subscription AWS has confirmed: accepting takes the card away, and
    # nothing but a confirmation would start the workspace again. Declining is
    # open whatever the state, because a request nobody can answer is worse
    # than one answered no.
    #
    # The card is stopped from Billing::SettleCancellationJob, after the commit,
    # so that nothing here can roll back around a cancellation Stripe has
    # already made and no row lock is held across a call to another service.
    def accept!(by:)
      refuse_unless_answerable!
      raise Refused, NOT_CONFIRMED unless license.active?
      raise Refused, ALREADY_BILLED if Payer.for(company).subscribed_through_aws?

      cancellation = company.with_lock do
        subscription_id = company.stripe_subscription_id
        # Measured while the workspace is still the card's: once it has moved,
        # Billing::CapacityWindow owes the card nothing for the hour.
        final_usage = FinalUsage.new(company, until_time: Time.current) if subscription_id.present?
        billed = final_usage&.billed

        note_the_debt_it_leaves_behind
        company.update!(**billing_terms)
        license.update!(company: company, proposal_state: "accepted", proposal_decided_at: Time.current)
        if subscription_id.present?
          hand_over_from_stripe(by: by, subscription_id: subscription_id, final_usage: final_usage, billed: billed)
        end
      end
      if cancellation
        SettleCancellationJob.perform_later(cancellation.id)
        notify_admins_of_the_cancellation(cancellation)
      end
      license
    end

    def decline!(by:)
      refuse_unless_answerable!

      license.update!(proposal_state: "declined", proposal_decided_at: Time.current)
    end

    private

    # Every administrator, the one who accepted included: only that one had read
    # that the card would be stopped.
    def notify_admins_of_the_cancellation(cancellation)
      company.billing_admins.find_each do |admin|
        BillingMailer.subscription_cancelled(cancellation, admin).deliver_later
      end
    end

    def refuse_unless_answerable!
      raise Refused, NOT_PENDING unless license.proposal_pending?
      raise Refused, NOT_PROPOSABLE unless license.proposable?
    end

    # Raising a second proposal replaces the first rather than queueing beside
    # it: the buyer has one subscription and one domain, so there is only ever
    # one question to answer.
    def propose!(company:, email:)
      raise Refused, NOT_PROPOSABLE unless license.proposable?
      raise Refused, ALREADY_BILLED if Payer.for(company).subscribed_through_aws?

      license.update!(proposed_company: company, proposed_by_email: email.to_s.downcase,
                      proposed_at: Time.current, proposal_decided_at: nil, proposal_state: "pending")
      license
    end

    # A workspace stopped for an unpaid card invoice starts again here, because
    # AWS pays for it now; `forget_billing_block` drops the link to the invoice
    # with the block. The debt is not forgiven, only no longer shown, so it is
    # logged rather than lost between two writes.
    def note_the_debt_it_leaves_behind
      url = company.billing_unpaid_invoice_url
      return if url.blank?

      Rails.logger.warn(
        "[MarketplaceLicenseProposal] company #{company.id} moves to AWS Marketplace owing an unpaid Stripe " \
        "invoice (#{url}); the workspace starts again and Stripe goes on collecting it"
      )
    end

    # The same measurement and final invoice an ordinary cancellation makes,
    # immediately rather than at the period's end: capacity is billed in arrears
    # for every hour it is offered, so letting the card run out would bill the
    # same hours twice. `stripe_customer_id` stays on the company, because the
    # settlement reaches Stripe through it; the subscription id goes onto the
    # cancellation, which is what stops it.
    def hand_over_from_stripe(by:, subscription_id:, final_usage:, billed:)
      final_usage.record!
      company.billing_cancellations.create!(
        user: by, cancels_at: Time.current, settlement_state: "cancelling",
        stripe_subscription_id: subscription_id, final_usage: billed.transform_keys(&:iso8601)
      )
    end

    # What the workspace becomes: active, because #accept! refuses anything AWS
    # has not confirmed. A block for an unpaid Stripe invoice lifts with the
    # rest -- the invoice is still owed in Stripe, which is where it is collected.
    def billing_terms
      { billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE,
        stripe_subscription_id: nil, billing_cancels_at: nil,
        billing_unpaid_invoice_url: nil, billing_event_at: Time.current,
        billing_state: "active", billing_block_reason: nil }
    end
  end
end
