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

    def self.pending_for(company) = MarketplaceLicense.proposed_to(company).first

    def initialize(license)
      @license = license
    end

    attr_reader :license

    def company = license.proposed_company

    # Applied in one go, with the Stripe subscription that was paying for the
    # workspace stopped in the same breath. See #hand_over_from_stripe for why
    # it is not left to run out.
    #
    # Only a subscription AWS has confirmed. Accepting a pending one cancels the
    # card in the same breath and leaves the workspace `awaiting_subscription`,
    # which nothing but a confirmation lifts -- and it cannot take a card again
    # either, because a pending licence is a live one. A subscription AWS never
    # confirms would strand a workspace that was paying perfectly well.
    #
    # Declining stays open whatever the state: an administrator may always say
    # no, and a request nobody can answer is worse than one answered no.
    def accept!(by:)
      refuse_unless_answerable!
      raise Refused, NOT_CONFIRMED unless license.active?
      raise Refused, ALREADY_BILLED if Payer.for(company).subscribed_through_aws?

      cancellation = nil
      company.with_lock do
        # Measured first, while the workspace is still the card's: FinalUsage
        # reads what it was offered, and a workspace already moved is offered
        # nothing. Memoised, so #record! below reports the same measurement.
        subscription_id = company.stripe_subscription_id
        final_usage = FinalUsage.new(company, until_time: Time.current) if subscription_id.present?
        billed = final_usage&.billed

        # Then every local write that can fail -- a validation, the partial
        # unique index on a live licence -- and only after them the call to
        # Stripe. The other order cancelled the card first and rolled the
        # transaction back around it, leaving a customer with no subscription,
        # no final invoice and a workspace still looking card-billed.
        company.update!(**billing_terms)
        license.update!(company: company, proposal_state: "accepted", proposal_decided_at: Time.current)
        if subscription_id.present?
          cancellation = hand_over_from_stripe(by: by, subscription_id: subscription_id,
                                               final_usage: final_usage, billed: billed)
        end
      end
      # Outside the lock: the final invoice is settled against Stripe, which is
      # a conversation with another service and no business holding a row.
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

    # Every administrator, the one who accepted included -- the same rule an
    # ordinary cancellation follows, and for the same reason: a workspace whose
    # subscription stops without the others hearing of it is a support ticket
    # the day it does. Only the admin who pressed the button had read that the
    # card would be stopped.
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
    # workspace -- which is why the id is passed in here rather than read off
    # the company, whose copy #billing_terms has just cleared.
    #
    # Called with the measurement already taken and the local rows already
    # written, so the only thing left that can fail is Stripe -- and a failure
    # there rolls back a transaction that has touched nothing of theirs.
    def hand_over_from_stripe(by:, subscription_id:, final_usage:, billed:)
      response = StripeClient.new.cancel_subscription(
        subscription_id: subscription_id, reason: nil, comment: nil
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
    # Always active: #accept! refuses anything AWS has not confirmed, so there
    # is no longer a case where the workspace has to wait. It used to have one,
    # and the wait had no end -- nothing but a confirmation lifted it, and the
    # workspace could not take a card again either.
    def billing_terms
      { billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE,
        stripe_subscription_id: nil, billing_cancels_at: nil,
        billing_unpaid_invoice_url: nil, billing_event_at: Time.current,
        billing_state: "active", billing_block_reason: nil }
    end
  end
end
