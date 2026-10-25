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
    DOMAIN_FREE = "There is no workspace at that domain to apply it to."
    ALREADY_BILLED = "That workspace already has an AWS Marketplace subscription."

    # The workspace is derived from the proved address and never passed in, so
    # there is no parameter here through which to aim a proposal somewhere else.
    def self.raise!(license:, email:)
      company = Company.find_by(email_domain: email.to_s.split("@").last.to_s.downcase)
      raise Refused, DOMAIN_FREE if company.nil?

      new(license).send(:propose!, company: company, email: email)
    end

    def self.pending_for(company) = MarketplaceLicense.proposed_to(company).first

    def initialize(license)
      @license = license
    end

    attr_reader :license

    def company = license.proposed_company

    # Applied in one go, with the Stripe subscription that was paying for the
    # workspace stopped in the same breath. See #hand_over_from_stripe for why
    # it is not left to run out.
    def accept!(by:)
      refuse_unless_answerable!
      raise Refused, ALREADY_BILLED if company.marketplace_license.present?

      cancellation = nil
      company.with_lock do
        cancellation = hand_over_from_stripe(by: by) if company.stripe_subscription_id.present?
        company.update!(**billing_terms)
        license.update!(company: company, proposal_state: "accepted", proposal_decided_at: Time.current)
      end
      # Outside the lock: the final invoice is settled against Stripe, which is
      # a conversation with another service and no business holding a row.
      SettleCancellationJob.perform_later(cancellation.id) if cancellation
      license
    end

    def decline!(by:)
      refuse_unless_answerable!

      license.update!(proposal_state: "declined", proposal_decided_at: Time.current)
    end

    private

    def refuse_unless_answerable!
      raise Refused, NOT_PENDING unless license.proposal_pending?
      raise Refused, NOT_PROPOSABLE unless license.proposable?
    end

    # Raising a second proposal replaces the first rather than queueing beside
    # it: the buyer has one subscription and one domain, so there is only ever
    # one question to answer.
    def propose!(company:, email:)
      raise Refused, NOT_PROPOSABLE unless license.proposable?
      raise Refused, ALREADY_BILLED if company.marketplace_license.present?

      license.update!(proposed_company: company, proposed_by_email: email.to_s.downcase,
                      proposed_at: Time.current, proposal_decided_at: nil, proposal_state: "pending")
      license
    end

    # The same measurement and the same final invoice an ordinary cancellation
    # makes, because the minutes Stripe has not counted are owed to whoever
    # billed the hour they happened in.
    #
    # Immediate, not at the period's end. Capacity is billed in arrears for
    # every hour it is offered (Billing::StripeClient#cancel_subscription), so
    # there is no paid-for remainder to run out — letting it run would bill the
    # same hours twice, once by Stripe and once by AWS.
    #
    # `stripe_customer_id` is deliberately kept: the settlement puts the last
    # metered hours on the final invoice and reaches Stripe through it. Only the
    # subscription id goes, so nothing later mistakes this for a card-billed
    # workspace.
    def hand_over_from_stripe(by:)
      final_usage = FinalUsage.new(company, until_time: Time.current)
      billed = final_usage.billed
      response = StripeClient.new.cancel_subscription(
        subscription_id: company.stripe_subscription_id, reason: nil, comment: nil
      )
      ended_at = SubscriptionState.from(response).ended_at || Time.current

      final_usage.record!
      company.billing_cancellations.create!(
        user: by, cancels_at: ended_at, settlement_state: "settling",
        final_usage: billed.transform_keys(&:iso8601), final_invoice_id: final_invoice_id(response)
      )
    end

    def final_invoice_id(subscription)
      invoice = subscription.try(:latest_invoice)
      invoice.respond_to?(:id) ? invoice.id : invoice.presence
    end

    # What the workspace becomes. A block for an unpaid Stripe invoice is lifted
    # with the rest — the workspace has a payer again, and the invoice is still
    # owed in Stripe, which is where it is collected.
    def billing_terms
      terms = { billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE,
                stripe_subscription_id: nil, billing_cancels_at: nil,
                billing_unpaid_invoice_url: nil, billing_event_at: Time.current }
      return terms.merge(billing_state: "active", billing_block_reason: nil) if license.active?

      # AWS discards metering sent before it confirms the agreement, so a
      # workspace whose licence is still pending waits rather than runs unbilled.
      terms.merge(billing_state: "blocked", billing_block_reason: "awaiting_subscription")
    end
  end
end
