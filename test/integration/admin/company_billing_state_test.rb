# frozen_string_literal: true

require "test_helper"

# Blocking a company for spending its free allowance is a one-way door unless
# somebody can open it again. A company with a Stripe customer can be moved back
# to `active` from here; one without would then run with nothing to bill through,
# which is only for a company we carry.
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

  test "a company with no Stripe customer cannot be made active by hand" do
    @company.update!(stripe_customer_id: nil)

    update!("active")

    assert_response :unprocessable_entity
    assert_match(/cannot be active without a Stripe customer/, response.body)
    assert @company.reload.billing_blocked?
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
