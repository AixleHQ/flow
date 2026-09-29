# frozen_string_literal: true

require "test_helper"

# Blocking a company for spending its free allowance is a one-way door unless
# somebody can open it again. Until Stripe is wired up, "someone is paying" is a
# platform administrator moving the company to `active`, and this is the path
# that does it.
class Admin::CompanyBillingStateTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company, :billing_blocked)
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
