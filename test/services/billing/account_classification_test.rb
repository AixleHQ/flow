# frozen_string_literal: true

require "test_helper"

class Billing::AccountClassificationTest < ActiveSupport::TestCase
  setup do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
  end

  def classify(company) = Billing::AccountClassification.of(company)

  test "a company paying through Stripe is an active paid customer billed by Stripe" do
    assert_equal({ account_status: "active_customer", account_type: "paid", billing_method: "saas_stripe" },
                 classify(create(:company, :subscribed)))
  end

  test "a customer whose cancellation takes effect at the end of the period is active until then" do
    company = create(:company, :subscribed, billing_cancels_at: 5.days.from_now)

    assert_equal "active_customer", classify(company)[:account_status]
  end

  test "a trial is active until its allowance is spent, and nobody invoices it yet" do
    assert_equal({ account_status: "trial_active", account_type: "paid", billing_method: nil },
                 classify(create(:company, :trialing)))
  end

  test "each reason a company is stopped for reads as its own status" do
    expected = {
      "allowance" => "trial_expired",
      "canceled" => "canceled",
      "payment_failed" => "locked_nonpayment",
      "awaiting_subscription" => "pending_activation"
    }

    Company::BILLING_BLOCK_REASONS.each do |reason|
      company = create(:company, :billing_blocked, billing_block_reason: reason)

      assert_equal expected.fetch(reason), classify(company)[:account_status], reason
    end
  end

  test "a company AWS bills for the hosted product is billed through the SaaS listing" do
    company = create(:company, :billing_blocked, billing_block_reason: "awaiting_subscription",
                                                 billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)

    assert_equal "saas_aws_marketplace", classify(company)[:billing_method]
  end

  test "a company we carry is managed and invoiced by nobody, whoever billed it before" do
    company = create(:company, :subscribed)
    company.update!(managed_by_aixle: true)

    assert_equal Company::BILLING_PROVIDER_STRIPE, company.billing_provider
    assert_equal({ account_status: "active_customer", account_type: "managed", billing_method: nil },
                 classify(company))
  end

  test "a suspended or archived company is inactive whatever its billing says" do
    suspended = create(:company, :subscribed)
    suspended.suspend!
    archived = create(:company, :trialing)
    archived.archive!

    assert_equal "inactive", classify(suspended)[:account_status]
    assert_equal "inactive", classify(archived)[:account_status]
  end

  test "every company of an AWS Marketplace installation is self-hosted through AWS; a self-hosted one has no method" do
    company = create(:company)

    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::AWS_MARKETPLACE))
    assert_equal "self_hosted_aws_marketplace", classify(company)[:billing_method]

    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SELF_HOSTED))
    assert_nil classify(company)[:billing_method]
  end
end
