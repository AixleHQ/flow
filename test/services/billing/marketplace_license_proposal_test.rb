# frozen_string_literal: true

require "test_helper"

# A subscription bought in AWS, and the workspace at the buyer's domain that
# already exists. The whole point of the class is that the second does not
# become the first's without somebody there agreeing.
class Billing::MarketplaceLicenseProposalTest < ActiveSupport::TestCase
  setup do
    @license = create(:marketplace_license, :active)
    @company = create(:company, email_domain: "northwind.example")
    @admin = create(:user)
  end

  def proposal = Billing::MarketplaceLicenseProposal.new(@license.reload)

  def propose(email: "dana@northwind.example")
    Billing::MarketplaceLicenseProposal.raise!(license: @license, email: email)
  end

  # -- Raising it ------------------------------------------------------------

  test "a proposal names the workspace at the proposer's own domain" do
    propose

    assert_equal @company, @license.reload.proposed_company
    assert_equal "dana@northwind.example", @license.proposed_by_email
    assert @license.proposal_pending?
  end

  # The workspace is never a parameter. It is looked up from the address, so
  # there is nothing to aim somewhere else.
  test "a domain with no workspace has nothing to propose to" do
    error = assert_raises(Billing::MarketplaceLicenseProposal::Refused) do
      propose(email: "dana@somewhere-else.example")
    end

    assert_equal Billing::MarketplaceLicenseProposal::DOMAIN_FREE, error.message
    assert_nil @license.reload.proposed_company
  end

  test "nothing is proposed while the licence already has a workspace" do
    @license.update!(company: create(:company))

    assert_raises(Billing::MarketplaceLicenseProposal::Refused) { propose }
  end

  test "nothing is proposed for a subscription AWS has finished" do
    @license.finish!

    assert_raises(Billing::MarketplaceLicenseProposal::Refused) { propose }
  end

  test "a workspace that AWS already bills is not asked a second time" do
    create(:marketplace_license, :active, company: @company)

    error = assert_raises(Billing::MarketplaceLicenseProposal::Refused) { propose }

    assert_equal Billing::MarketplaceLicenseProposal::ALREADY_BILLED, error.message
  end

  # A workspace keeps the licences it has finished with. An ended one that still
  # answered "this workspace already has a subscription" refused the customer
  # who cancelled and subscribed again -- which is what our own screen tells
  # them to do -- and left them paying for nothing.
  test "a subscription that ended does not stand in the way of the next one" do
    create(:marketplace_license, :ended, company: @company)

    propose

    assert_equal @company, @license.reload.proposed_company
    assert @license.proposal_pending?
  end

  test "and the next one binds, because the ended one no longer holds the slot" do
    create(:marketplace_license, :ended, company: @company)
    propose

    proposal.accept!(by: @admin)

    assert_equal @company, @license.reload.company
    assert_equal 2, @company.marketplace_licenses.count, "the finished one is kept: it is a billing record"
    assert_equal @license, @company.reload.marketplace_license, "and `the` licence means the live one"
  end

  # One subscription, one domain, one question. A buyer who asks again is
  # asking the same thing.
  test "proposing again replaces the proposal rather than queueing beside it" do
    propose
    proposal.decline!(by: @admin)

    propose

    assert @license.reload.proposal_pending?
    assert_nil @license.proposal_decided_at
  end

  # -- Accepting it ----------------------------------------------------------

  test "accepting binds the licence and moves the workspace onto AWS" do
    propose

    proposal.accept!(by: @admin)

    assert_equal @company, @license.reload.company
    assert_equal Company::BILLING_PROVIDER_AWS_MARKETPLACE, @company.reload.billing_provider
    assert @company.billing_active?
    assert_equal "accepted", @license.proposal_state
  end

  # What the measurement reads to split the hour the switch happened in. Without
  # it AWS is sent the whole of that hour, including the part that was free or
  # already on the old payer's final invoice.
  test "accepting records when AWS took over" do
    propose
    travel_to(Time.utc(2026, 10, 25, 18, 36)) { proposal.accept!(by: @admin) }

    assert_equal Time.utc(2026, 10, 25, 18, 36), @company.reload.billing_provider_since
  end

  # AWS discards metering sent before it confirms the agreement, so a workspace
  # whose licence is still pending waits rather than runs unbilled.
  # Accepting cancels the card in the same breath, and only a confirmation
  # starts the workspace again. A subscription AWS never confirms would leave a
  # workspace that was paying perfectly well with nothing paying for it and no
  # way to add a card, because a pending licence is a live one.
  test "a subscription AWS has not confirmed cannot be applied yet" do
    @license.update!(subscription_state: "pending")
    @company.update!(stripe_customer_id: "cus_1", stripe_subscription_id: "sub_1")
    propose

    error = assert_raises(Billing::MarketplaceLicenseProposal::Refused) { proposal.accept!(by: @admin) }

    assert_equal Billing::MarketplaceLicenseProposal::NOT_CONFIRMED, error.message
    assert @company.reload.billing_active?, "the workspace it was paying for is untouched"
    assert_equal "sub_1", @company.stripe_subscription_id, "and so is the card paying for it"
    assert @license.reload.proposal_pending?, "the request stands; it is answerable once AWS confirms"
  end

  # The request is still a request. An administrator may always say no, and one
  # nobody can answer is worse than one answered no.
  test "an unconfirmed subscription can still be declined" do
    @license.update!(subscription_state: "pending")
    propose

    proposal.decline!(by: @admin)

    assert_equal "declined", @license.reload.proposal_state
  end

  # The workspace has a payer again, so what stopped it no longer holds: AWS
  # pays for it now, and a card that failed for capacity AWS no longer bills
  # must not keep it stopped -- the same rule the Stripe webhook follows.
  #
  # The debt is not forgiven. Stripe goes on collecting it and it is still owed
  # there; what the workspace loses is the link to it, because
  # `forget_billing_block` clears that field on every save of a company that is
  # not blocked. Deliberate, logged, and the one part of this a customer can
  # fairly complain about.
  test "a workspace stopped for an unpaid invoice runs again" do
    @company.update!(billing_state: "blocked", billing_block_reason: "payment_failed",
                     billing_unpaid_invoice_url: "https://invoice.example/1")
    propose

    proposal.accept!(by: @admin)

    assert @company.reload.billing_active?
    assert_nil @company.billing_block_reason
    assert_nil @company.billing_unpaid_invoice_url
  end

  test "an answered proposal cannot be answered again" do
    propose
    proposal.accept!(by: @admin)

    error = assert_raises(Billing::MarketplaceLicenseProposal::Refused) { proposal.accept!(by: @admin) }

    assert_equal Billing::MarketplaceLicenseProposal::NOT_PENDING, error.message
  end

  # -- Declining it ----------------------------------------------------------

  test "declining leaves the licence bound to nothing" do
    propose

    proposal.decline!(by: @admin)

    assert_nil @license.reload.company
    assert_equal "declined", @license.proposal_state
    assert_equal Company::BILLING_PROVIDER_NONE, @company.reload.billing_provider
  end
end

# -- The Stripe subscription that was paying for it --------------------------
#
# Deliberately not a subclass of the suite above: these are the same scenarios
# with a card behind them, not extra cases, and inheriting the parent's tests
# would re-run every one of them against a payment provider they never meant to
# reach.
class Billing::MarketplaceLicenseProposalStripeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @license = create(:marketplace_license, :active)
    @company = create(:company, email_domain: "northwind.example", billing_state: "active",
                                stripe_customer_id: "cus_1", stripe_subscription_id: "sub_1")
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 2)
    @admin = create(:user)
    @client = FakeStripeClient.new
    @client.add_subscription(id: "sub_1")
    Billing::StripeClient.stubs(:new).returns(@client)
  end

  def proposal = Billing::MarketplaceLicenseProposal.new(@license.reload)

  def propose = Billing::MarketplaceLicenseProposal.raise!(license: @license, email: "dana@northwind.example")

  def cancellation = @company.billing_cancellations.sole

  # Immediate, not at the period's end: capacity is billed in arrears, so the
  # rest of a period is not paid for, and leaving it to run would bill the
  # same hours to Stripe and to AWS both.
  test "accepting records the card subscription as one to stop" do
    propose

    proposal.accept!(by: @admin)

    assert_equal Company::BILLING_PROVIDER_AWS_MARKETPLACE, @company.reload.billing_provider
    assert_nil @company.stripe_subscription_id, "nothing later should read this as a card-billed workspace"
    assert cancellation.cancelling?
    assert_equal "sub_1", cancellation.stripe_subscription_id
    assert_enqueued_with(job: Billing::SettleCancellationJob, args: [ cancellation.id ])
  end

  # Stripe is told after the commit, from the job, so nothing here can roll
  # back around a subscription Stripe has already cancelled -- and the row lock
  # is never held across a call to another service.
  test "the card is stopped by the settlement job, not inside the handover" do
    propose

    proposal.accept!(by: @admin)
    assert_equal "active", @client.subscriptions.fetch("sub_1")[:status], "nothing reaches Stripe in the transaction"

    perform_enqueued_jobs(only: Billing::SettleCancellationJob)

    assert_equal "canceled", @client.subscriptions.fetch("sub_1")[:status]
    assert_equal "settled", cancellation.reload.settlement_state
  end

  # The settlement puts the last metered hours on the final invoice and
  # reaches Stripe through the customer, so the customer has to survive.
  test "the Stripe customer survives, because the final invoice is settled through it" do
    propose

    proposal.accept!(by: @admin)

    assert_equal "cus_1", @company.reload.stripe_customer_id
  end

  # The same rule an ordinary cancellation follows: only the admin who pressed
  # the button had read that the card would be stopped.
  test "every administrator hears that the card was stopped, not just the one who accepted" do
    deciding = create(:user, :admin, :onboarding_completed, company: @company)
    create(:user, :admin, :onboarding_completed, company: @company)
    propose

    assert_enqueued_emails 2 do
      proposal.accept!(by: deciding)
    end
  end

  test "the minutes Stripe has not counted are recorded against the cancellation" do
    CompanyCapacityChange.record!(company_id: @company.id, max_sessions: 2, occurred_at: 2.hours.ago)
    propose

    proposal.accept!(by: @admin)

    assert_equal @admin, cancellation.user
    assert cancellation.final_usage.any?, "the hours Stripe never saw are what the final invoice is for"
  end

  # The workspace keeps running throughout. An ordinary cancellation stops it
  # -- there would be nobody paying -- and here AWS takes over in the same
  # transaction, so the state that stops it is never reached.
  test "the workspace is never stopped on the way across" do
    propose

    proposal.accept!(by: @admin)

    assert @company.reload.billing_active?
    assert_nil @company.billing_block_reason
  end

  # The handover is done whether or not Stripe can be reached right now; the
  # card is stopped when it can be, and the job retries until then.
  test "a payment provider that cannot be reached does not hold the handover up" do
    @client.failure = "unreachable"
    propose

    proposal.accept!(by: @admin)

    assert_equal @company, @license.reload.company
    assert_equal Company::BILLING_PROVIDER_AWS_MARKETPLACE, @company.reload.billing_provider
    assert cancellation.cancelling?
  end
end
