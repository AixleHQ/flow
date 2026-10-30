# frozen_string_literal: true

require "test_helper"

class Billing::PayerTest < ActiveSupport::TestCase
  def deployment!(mode)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
  end

  setup { deployment!(Deployment::SAAS) }

  test "a company reports the provider on its column" do
    company = create(:company)

    assert_equal Company::BILLING_PROVIDER_NONE, company.billing_payer.provider
    assert company.billing_payer.none?
    assert_not company.billing_payer.stripe?

    company.update!(billing_provider: Company::BILLING_PROVIDER_STRIPE)

    assert company.billing_payer.stripe?
    assert_not company.billing_payer.none?
  end

  test "no company at all reads as no provider rather than raising" do
    payer = Billing::Payer.for(nil)

    assert_equal Company::BILLING_PROVIDER_NONE, payer.provider
    assert payer.none?
    assert_not payer.bills?
  end

  test "an unrecognised provider is refused by the model" do
    company = build(:company, billing_provider: "paypal")

    assert_not company.valid?
    assert_includes company.errors[:billing_provider], "is not included in the list"
  end

  # bills? is the expression that was spelled four different ways. These pin all
  # four of its inputs, because the whole point of the object is that one answer
  # now serves every caller.
  test "where we host, a company nobody carries is billed for" do
    assert create(:company).billing_payer.bills?
  end

  test "where we host, a company we carry is not" do
    assert_not create(:company, :managed_by_aixle).billing_payer.bills?
  end

  test "outside the hosted product nobody is billed for by us" do
    company = create(:company)

    deployment!(Deployment::SELF_HOSTED)
    assert_not company.billing_payer.bills?

    deployment!(Deployment::AWS_MARKETPLACE)
    assert_not company.billing_payer.bills?
  end

  # A company that has never paid still has its minutes metered and reported as
  # unbilled, so having no provider attached must not make it unbillable.
  test "having no provider attached does not stop a company being billed for" do
    company = create(:company)

    assert company.billing_payer.none?
    assert company.billing_payer.bills?
  end

  test "a subscribed company carries the provider and is billed for" do
    company = create(:company, :subscribed, billing_provider: Company::BILLING_PROVIDER_STRIPE)

    assert company.billing_payer.stripe?
    assert company.billing_payer.bills?
  end

  # Three paths write a Stripe customer and the column has to be true for all of
  # them, or the admin shows `none` beside a company that is paying.
  test "a company that acquires a Stripe customer records Stripe as its payer" do
    company = create(:company)
    assert company.billing_payer.none?

    company.update!(stripe_customer_id: "cus_new")

    assert company.billing_payer.stripe?
  end

  # While AWS can still bill it. A live subscription is what makes a second
  # payer a second bill for the same capacity.
  test "a customer id left over from before cannot re-point a company AWS bills" do
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    create(:marketplace_license, :active, company: company)

    company.update!(stripe_customer_id: "cus_leftover")

    assert company.billing_payer.aws_marketplace?
  end

  # And once it cannot. A customer who unsubscribes keeps `billing_provider` --
  # nothing re-points it -- so keying the refusal on the payer left them unable
  # to pay by card ever again, with the workspace stopped and their work in it.
  test "a workspace whose subscription ended may be paid for by card" do
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    create(:marketplace_license, :ended, company: company)

    company.update!(stripe_customer_id: "cus_new")

    assert company.billing_payer.stripe?
  end

  test "bounding and the worker minimum follow the installation until a payer changes them" do
    company = create(:company)

    assert_not company.billing_payer.requires_bound?
    assert_equal 1, company.billing_payer.minimum_workers

    deployment!(Deployment::AWS_MARKETPLACE)

    assert company.billing_payer.requires_bound?
    assert_equal Deployment::MARKETPLACE_MINIMUM_WORKERS, company.billing_payer.minimum_workers
  end
end
