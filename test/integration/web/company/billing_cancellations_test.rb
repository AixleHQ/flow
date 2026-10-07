# frozen_string_literal: true

require "test_helper"

# Stopping at the end of the billing period, and taking that back. Stripe is the
# fake; what is asserted is what the company row, the cancellation record and
# the outbox of mail say afterwards.
class Web::Company::BillingCancellationsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    @client = FakeStripeClient.new
    Billing::StripeClient.stubs(:new).returns(@client)
    @company = create(:company, :subscribed)
    @period_end = 20.days.from_now.change(usec: 0)
    @client.add_subscription(id: @company.stripe_subscription_id, period_end: @period_end)
    @admin = create(:user, :onboarding_completed, company: @company, membership_role: "admin",
                    password: AuthHelper::TEST_PASSWORD)
    @other_admin = create(:user, :onboarding_completed, company: @company, membership_role: "admin")
    create(:user, :onboarding_completed, company: @company, membership_role: "employee")
    sign_in_as(@admin)
  end

  test "an admin schedules the end of the subscription for the end of the period" do
    post company_billing_cancellation_path, params: { reason: "too_expensive", comment: "Budget cut" }

    assert_redirected_to company_settings_billing_path
    update = @client.subscription_updates.sole
    assert_equal true, update[:cancel_at_period_end] # rubocop:disable Minitest/AssertTruthy
    assert_equal({ feedback: "too_expensive", comment: "Budget cut" }, update[:cancellation_details])

    @company.reload
    assert @company.billing_active?, "the company runs until the period ends"
    assert_equal "cancelling", @company.billing_status
    assert_equal @period_end, @company.billing_cancels_at

    cancellation = @company.billing_cancellations.sole
    assert_equal @admin, cancellation.user
    assert_equal "too_expensive", cancellation.reason
    assert_equal "Budget cut", cancellation.comment
  end

  test "every admin hears of it, and nobody else" do
    assert_enqueued_emails 2 do
      post company_billing_cancellation_path, params: { reason: "unused" }
    end
  end

  test "the reason is optional" do
    post company_billing_cancellation_path

    assert_nil @company.billing_cancellations.sole.reason
    assert_not @client.subscription_updates.sole[:cancellation_details].values.any?(&:present?)
  end

  test "pressing it twice schedules once and mails once" do
    post company_billing_cancellation_path, params: { reason: "unused" }

    assert_enqueued_emails 0 do
      post company_billing_cancellation_path, params: { reason: "unused" }
    end
    assert_redirected_to company_settings_billing_path
    assert_nil flash[:alert]
    assert_equal 1, @company.billing_cancellations.count
    assert_equal 1, @client.subscription_updates.size
  end

  test "a reason that is not on the list is refused" do
    post company_billing_cancellation_path, params: { reason: "because" }

    assert_match(/listed reasons/, flash[:alert])
    assert_empty @client.subscription_updates
  end

  # A company on its free allowance has no card and nothing to cancel.
  test "a trialing company has nothing to cancel" do
    @company.update!(billing_state: "trialing", stripe_subscription_id: nil)

    post company_billing_cancellation_path

    assert_match(/paying workspace/, flash[:alert])
    assert_empty @company.billing_cancellations
  end

  test "when Stripe cannot be reached nothing changes and the admin is told" do
    @client.failure = "APIConnectionError: could not reach Stripe"

    assert_enqueued_emails 0 do
      post company_billing_cancellation_path, params: { reason: "unused" }
    end

    assert_match(/Nothing has changed/, flash[:alert])
    @company.reload
    assert_equal "active", @company.billing_status
    assert_empty @company.billing_cancellations
  end

  test "a scheduled cancellation can be taken back before the date" do
    post company_billing_cancellation_path, params: { reason: "unused" }

    delete company_billing_cancellation_path

    assert_redirected_to company_settings_billing_path
    assert_equal false, @client.subscriptions[@company.stripe_subscription_id][:cancel_at_period_end] # rubocop:disable Minitest/RefuteFalse
    @company.reload
    assert_equal "active", @company.billing_status
    assert_nil @company.billing_cancels_at
    assert_not_nil @company.billing_cancellations.sole.resumed_at, "the reason is kept, marked as taken back"
  end

  test "taking back a cancellation that was never made changes nothing" do
    delete company_billing_cancellation_path

    assert_redirected_to company_settings_billing_path
    assert_empty @client.subscription_updates
  end
end
