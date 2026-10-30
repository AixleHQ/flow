# frozen_string_literal: true

require "test_helper"

# Blocking a company for spending its free allowance is a one-way door unless
# somebody can open it again. A company with a Stripe customer can be moved back
# to `active` from here. One without would then run with nothing to bill
# through, so it is given a new free allowance instead, and needs a card once
# that is spent.
class Admin::CompanyBillingStateTest < ActionDispatch::IntegrationTest
  setup do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    @company = create(:company, :billing_blocked, stripe_customer_id: "cus_blocked")
    @admin = create(:user, :super_admin, :onboarding_completed, company: create(:company),
                    password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@admin)
  end

  def update!(billing_state)
    patch admin_company_path(@company), params: {
      company: { name: @company.name, email_domain: @company.email_domain, billing_state: billing_state }
    }
  end

  test "an administrator can start a company running again" do
    update!("active")

    assert_response :redirect
    assert @company.reload.billing_active?
  end

  test "a company with no Stripe customer made active by hand starts a new trial" do
    @company.update!(stripe_customer_id: nil)
    CompanyCapacityUsage.record!(company_id: @company.id, period_start: 2.days.ago.beginning_of_hour,
                                 quantity_seconds: Billing::Trial.default_hours * 3600)

    freeze_time do
      update!("active")

      assert_redirected_to admin_company_path(@company)
      assert_match(/is on a trial until the end of .+, on one worker/, flash[:notice])
      @company.reload
      assert @company.billing_trialing?
      assert_equal Time.current, @company.trial_started_at
      assert_equal 720, @company.trial_hours
      assert_equal 0, Billing::Trial.used_seconds(@company)
    end
  end

  test "and can put one back on the allowance" do
    update!("trialing")

    assert @company.reload.billing_trialing?
  end

  # The column drives admission and metering, so a typo must not become a state
  # nothing understands.
  test "a state nobody recognises is refused" do
    update!("paid_probably")

    assert @company.reload.billing_blocked?
  end

  test "the index shows which companies are on the allowance" do
    get admin_companies_path

    assert_response :success
    assert_match "blocked", response.body
  end
end
