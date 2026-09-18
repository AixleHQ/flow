# frozen_string_literal: true

require "test_helper"

# Regression coverage for a privilege-escalation path found in review: the
# impersonation marker is only a cookie key, so it must never outlive the session
# that earned it, and it must never be re-seeded into somebody else's session.
class Web::ImpersonationSessionHygieneTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @operator = create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD,
                                            password_confirmation: AuthHelper::TEST_PASSWORD)
    @victim = create(:user, :onboarding_completed, company: @company,
                            password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    @bystander = create(:user, :onboarding_completed, company: @company,
                               password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
  end

  test "signing out during an impersonation does not leave an operator identity behind" do
    sign_in_as(@operator)
    post impersonate_admin_user_path(@victim)

    # The support session ends the ordinary way rather than via stop_impersonate.
    delete logout_path

    # An unrelated, non-privileged person signs in on the same browser.
    sign_in_as(@bystander)

    get admin_root_path

    assert_redirected_to "/login"
  end

  test "stop_impersonating returns to the account that actually authenticated" do
    sign_in_as(@operator)
    post impersonate_admin_user_path(@victim)

    post stop_impersonate_admin_user_path(@victim)

    get admin_root_path
    assert_response :success
  end

  test "revoking the operator's session ends the impersonation with it" do
    sign_in_as(@operator)
    post impersonate_admin_user_path(@victim)

    AuthSession.live.find_by(user: @operator).revoke!

    get admin_root_path

    assert_redirected_to "/login"
  end
end
