# frozen_string_literal: true

require "test_helper"

# CAP-4: time-based one-time codes, as a STEP-UP method.
#
# TOTP proves possession of a device, not identity, so it never starts a session
# — which is how a company can require it without the conjunctive proof
# semantics the spine defers.
class Web::TotpStepUpTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :onboarding_completed, company: @company,
                          password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    @password = IdentityProvider.password
    @totp = IdentityProvider.deployment!("totp")
  end

  def enrol!
    sign_in_as(@user)
    post totp_path
    secret = JSON.parse(response.body)["secret"]
    post confirm_totp_path, params: { code: ROTP::TOTP.new(secret).now }
    secret
  end

  test "a secret that was generated but never confirmed is inert" do
    sign_in_as(@user)

    post totp_path

    assert_response :success
    refute_predicate @user.reload, :totp_enabled?, "an unconfirmed secret must not count as enabled"
  end

  test "a correct code turns it on" do
    enrol!

    assert @user.reload.totp_enabled?
    assert_not_nil @user.totp_confirmed_at
  end

  test "a wrong code does not" do
    sign_in_as(@user)
    post totp_path

    post confirm_totp_path, params: { code: "000000" }

    refute_predicate @user.reload, :totp_enabled?
  end

  test "a company requiring TOTP is satisfied by proving it at step-up" do
    secret = enrol!
    # This company accepts TOTP only. The session proved a password, so it must
    # step up — and a code is what satisfies it.
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @password).update!(enabled: false)
    user_session = UserSession.live.find_by(user: @user)

    get company_projects_path
    assert_redirected_to step_up_path

    post step_up_path, params: { step_up: { kind: "totp", code: ROTP::TOTP.new(secret).now } }

    assert_redirected_to company_projects_path
    assert_includes user_session.reload.proved_provider_ids, @totp.id
  end

  test "a wrong code at step-up is refused" do
    enrol!
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @password).update!(enabled: false)

    post step_up_path, params: { step_up: { kind: "totp", code: "000000" } }

    assert_redirected_to step_up_path(error: "invalid_credentials")
  end

  test "turning it off clears the secret" do
    enrol!

    delete totp_path

    refute_predicate @user.reload, :totp_enabled?
    assert_nil @user.totp_secret
  end
end
