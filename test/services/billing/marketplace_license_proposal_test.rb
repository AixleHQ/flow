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

  # Found for real on 26 October. A workspace keeps the licences it has finished
  # with, and an ended one went on answering "this workspace already has a
  # subscription" -- so a customer who cancelled and subscribed again, which is
  # what our own screen tells them to do, was refused and left paying for
  # nothing.
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
  test "a workspace waits when the subscription is not confirmed yet" do
    @license.update!(subscription_state: "pending")
    propose

    proposal.accept!(by: @admin)

    assert @company.reload.billing_blocked?
    assert_equal "awaiting_subscription", @company.billing_block_reason
  end

  # The workspace has a payer again, so what stopped it no longer holds. The
  # unpaid invoice is still owed, in Stripe, which is where it is collected.
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

  setup do
    @license = create(:marketplace_license, :active)
    @company = create(:company, email_domain: "northwind.example", billing_state: "active",
                                stripe_customer_id: "cus_1", stripe_subscription_id: "sub_1")
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 2)
    @admin = create(:user)
    @client = mock
    Billing::StripeClient.stubs(:new).returns(@client)
  end

  def proposal = Billing::MarketplaceLicenseProposal.new(@license.reload)

  def propose = Billing::MarketplaceLicenseProposal.raise!(license: @license, email: "dana@northwind.example")

  def expect_cancellation
    @client.expects(:cancel_subscription)
           .with(subscription_id: "sub_1", reason: nil, comment: nil)
           .returns(Stripe::Subscription.construct_from(id: "sub_1", status: "canceled",
                                                        ended_at: Time.current.to_i,
                                                        latest_invoice: "in_final"))
  end

  # Immediate, not at the period's end: capacity is billed in arrears, so the
  # rest of a period is not paid for, and leaving it to run would bill the
  # same hours to Stripe and to AWS both.
  test "accepting stops the card subscription in the same breath" do
    expect_cancellation
    propose

    proposal.accept!(by: @admin)

    assert_equal Company::BILLING_PROVIDER_AWS_MARKETPLACE, @company.reload.billing_provider
    assert_nil @company.stripe_subscription_id, "nothing later should read this as a card-billed workspace"
  end

  # The settlement puts the last metered hours on the final invoice and
  # reaches Stripe through the customer, so the customer has to survive.
  test "the Stripe customer survives, because the final invoice is settled through it" do
    expect_cancellation
    propose

    proposal.accept!(by: @admin)

    assert_equal "cus_1", @company.reload.stripe_customer_id
    assert_enqueued_with(job: Billing::SettleCancellationJob)
  end

  test "the minutes Stripe has not counted are recorded against the cancellation" do
    expect_cancellation
    CompanyCapacityChange.record!(company_id: @company.id, max_sessions: 2, occurred_at: 2.hours.ago)
    propose

    proposal.accept!(by: @admin)

    cancellation = @company.billing_cancellations.sole
    assert_equal @admin, cancellation.user
    assert cancellation.final_usage.any?, "the hours Stripe never saw are what the final invoice is for"
  end

  # The workspace keeps running throughout. An ordinary cancellation stops it
  # -- there would be nobody paying -- and here AWS takes over in the same
  # transaction, so the state that stops it is never reached.
  test "the workspace is never stopped on the way across" do
    expect_cancellation
    propose

    proposal.accept!(by: @admin)

    assert @company.reload.billing_active?
    assert_nil @company.billing_block_reason
  end

  # Stripe refusing leaves everything as it was rather than half-moved.
  test "a payment provider that cannot be reached changes nothing" do
    @client.expects(:cancel_subscription).raises(Billing::StripeClient::Error, "unreachable")
    propose

    assert_raises(Billing::StripeClient::Error) { proposal.accept!(by: @admin) }

    assert_nil @license.reload.company
    assert_equal "sub_1", @company.reload.stripe_subscription_id
    assert_equal Company::BILLING_PROVIDER_STRIPE, @company.billing_provider
  end
end
