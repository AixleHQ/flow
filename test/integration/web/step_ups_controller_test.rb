# frozen_string_literal: true

require "test_helper"

# Step-up re-authentication (AD-5): the branch a live session lands on when it
# no longer satisfies the company it is entering.
class Web::StepUpsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @password = IdentityProvider.password
    @google = IdentityProvider.deployment!("google")
    @user = create(:user, :onboarding_completed, company: @company,
                          password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
  end

  def prove_only(provider)
    auth_session = AuthSession.live.find_by(user: @user)
    auth_session.proofs.destroy_all
    Auth::SessionService.append_proof(auth_session, provider)
    auth_session
  end

  test "an anonymous visitor is sent to login, not to step-up" do
    get step_up_path

    assert_redirected_to login_path
  end

  test "a session that already satisfies the company is sent onward" do
    sign_in_as(@user)

    get step_up_path

    assert_redirected_to company_projects_path
  end

  test "a company with no method this session can prove still renders, without a password form" do
    sign_in_as(@user)
    prove_only(@google)
    # Password stays disabled, so the step-up page has nothing to offer but a
    # pointer at the administrator — it must render rather than loop.
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @password).update!(enabled: false)
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @google).update!(enabled: false)

    get step_up_path

    assert_response :success
  end

  test "a password step-up is refused when the company no longer accepts passwords" do
    sign_in_as(@user)
    prove_only(@google)
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @password).update!(enabled: false)

    post step_up_path, params: { step_up: { password: AuthHelper::TEST_PASSWORD } }

    assert_redirected_to step_up_path(error: "method_not_allowed")
  end

  def fake_request(path)
    Rack::Attack::Request.new(Rack::MockRequest.env_for("http://example.test#{path}"))
  end

  test "every credential-accepting endpoint is throttled, and only callbacks are safelisted" do
    # The spine's own convention. The /auth/ prefix used to be safelisted
    # wholesale, which silently exempted the OIDC *start* action — an endpoint a
    # person triggers, not an identity provider.
    %w[step_up/ip credential/ip magic_link/email].each do |name|
      assert_includes Rack::Attack.throttles.keys, name
    end

    safelist = Rack::Attack.safelists["allow-oauth-callbacks"]
    assert_not_nil safelist
    refute safelist.matched_by?(fake_request("/auth/oidc/7/start")),
           "the OIDC start action must not be exempt from throttling"
    assert safelist.matched_by?(fake_request("/auth/google/callback"))
  end

  test "the step-up password endpoint is throttled" do
    # It re-verifies the account password inside an already-authenticated
    # session, so it is a second password oracle and must not be reachable at
    # /login's expense. Pinning the registration, since this repo does not
    # exercise Rack::Attack end to end.
    assert_includes Rack::Attack.throttles.keys, "step_up/ip"
  end
end
