# frozen_string_literal: true

require "test_helper"

# CAP-3: a company signs in through its own OpenID Connect provider. Exercises
# the real redirect: PKCE and the nonce are minted by the start action, held
# server-side by Auth::State, and consumed exactly once by the callback.
class Web::OidcSignInTest < ActionDispatch::IntegrationTest
  ISSUER = "https://idp.example.test"

  setup do
    # The PKCE verifier and the OIDC nonce live in Rails.cache, and the test env
    # is :null_store — every login would look replayed. Same MemoryStore stub the
    # Oauth::State test uses.
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)

    @company = create(:company, :auto_accept, email_domain: "oidc-acme.test")
    @provider = create(:identity_provider, company: @company, kind: "oidc",
                                           name: "Acme SSO",
                                           config: { "issuer" => ISSUER, "client_id" => "our-client" })
    @provider.client_secret = "our-secret"
    @provider.save!
    create(:company_auth_policy, company: @company, identity_provider: @provider, enabled: true)

    @rsa = OpenSSL::PKey::RSA.generate(2048)
    @jwk = JSON::JWK.new(@rsa.public_key, kid: "test-kid")

    stub_request(:get, "#{ISSUER}/.well-known/openid-configuration").to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { issuer: ISSUER, authorization_endpoint: "#{ISSUER}/authorize",
              token_endpoint: "#{ISSUER}/token", jwks_uri: "#{ISSUER}/jwks" }.to_json
    )
    stub_request(:get, "#{ISSUER}/jwks").to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: JSON::JWK::Set.new(@jwk).as_json.to_json
    )
  end

  # No assertion here on purpose: a helper that asserts reads as a test to the
  # linter, and parsing response.location already fails loudly if the start
  # action did not redirect.
  def start_and_capture_state
    post oidc_start_path(id: @provider.id)
    query = Rack::Utils.parse_query(URI.parse(response.location.to_s).query)
    [ query["state"], query["nonce"] ]
  end

  def build_token_stub(nonce, email: "person@oidc-acme.test", sub: "oidc-subject-1")
    jwt = JSON::JWT.new(
      iss: ISSUER, aud: "our-client", sub: sub,
      exp: 10.minutes.from_now.to_i, iat: Time.current.to_i, nonce: nonce,
      email: email, email_verified: true, name: "OIDC Person"
    )
    jwt.kid = "test-kid"
    stub_request(:post, "#{ISSUER}/token").to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { access_token: "at", token_type: "Bearer", id_token: jwt.sign(@rsa, :RS256).to_s }.to_json
    )
  end

  test "a first-time user from the company's IdP is signed in and lands in that company" do
    state, nonce = start_and_capture_state
    build_token_stub(nonce)

    assert_difference "User.count", 1 do
      get oidc_callback_path(code: "the-code", state: state)
    end

    user = User.find_by(email: "person@oidc-acme.test")
    assert_equal "oidc-subject-1", user.user_identities.first.subject
    assert UserSession.live.exists?(user: user)
    assert_redirected_to company_projects_path
  end

  test "the state is single use: a replayed callback is refused" do
    state, nonce = start_and_capture_state
    build_token_stub(nonce)
    get oidc_callback_path(code: "the-code", state: state)

    assert_no_difference "User.count" do
      get oidc_callback_path(code: "the-code", state: state)
    end

    assert_redirected_to login_path(error: "oauth_failed")
  end

  test "a tampered state is refused before any code is exchanged" do
    get oidc_callback_path(code: "the-code", state: "not-a-signed-state")

    assert_redirected_to login_path(error: "oauth_failed")
    assert_not_requested :post, "#{ISSUER}/token"
  end

  test "the post-login destination cannot be turned into an open redirect" do
    # A signed state does not make an attacker-supplied destination safe, and
    # browsers normalise "/\\host" and control characters into protocol-relative
    # cross-site URLs.
    [ "//evil.test/path", "/\\evil.test", "/\tevil", "https://evil.test" ].each do |hostile|
      post oidc_start_path(id: @provider.id), params: { return_to: hostile }
      state = Rack::Utils.parse_query(URI.parse(response.location.to_s).query)["state"]
      nonce = Rack::Utils.parse_query(URI.parse(response.location.to_s).query)["nonce"]
      build_token_stub(nonce)

      get oidc_callback_path(code: "the-code", state: state)

      assert_redirected_to company_projects_path, "#{hostile.inspect} must not survive as a destination"
    end
  end

  test "an admin of the owning company can start a connection that is not enabled yet" do
    # AD-7 wants a connection proved before it is enabled, and the proof is a
    # sign-in through it. Without this the two guards deadlock: no sign-in until
    # enabled, no enabling until signed in.
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @provider).update!(enabled: false)
    admin = create(:user, :onboarding_completed, company: @company, membership_role: "admin",
                          password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    sign_in_as(admin)

    post oidc_start_path(id: @provider.id)

    assert_response :redirect
    assert_match ISSUER, response.location
  end

  test "verifying a connection returns to the screen that asked for it" do
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @provider).update!(enabled: false)
    admin = create(:user, :onboarding_completed, company: @company, membership_role: "admin",
                          email: "admin@oidc-acme.test",
                          password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    create(:user_identity, user: admin, identity_provider: @provider, subject: "oidc-admin-1")
    sign_in_as(admin)
    state, nonce = start_and_capture_state
    build_token_stub(nonce, email: admin.email, sub: "oidc-admin-1")

    get oidc_callback_path(code: "the-code", state: state)

    assert_redirected_to company_auth_policies_path
  end

  test "a member who is not an admin cannot start a connection that is not enabled" do
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @provider).update!(enabled: false)
    member = create(:user, :onboarding_completed, company: @company,
                           password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    sign_in_as(member)

    post oidc_start_path(id: @provider.id)

    assert_redirected_to login_path(error: "oauth_failed")
  end

  test "an admin of another company cannot start this company's disabled connection" do
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @provider).update!(enabled: false)
    outsider = create(:user, :onboarding_completed, company: create(:company), membership_role: "admin",
                             password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    sign_in_as(outsider)

    post oidc_start_path(id: @provider.id)

    assert_redirected_to login_path(error: "oauth_failed")
  end

  test "a disabled connection cannot be started by guessing its id" do
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @provider).update!(enabled: false)

    post oidc_start_path(id: @provider.id)

    assert_redirected_to login_path(error: "oauth_failed")
  end

  test "SSO discovery routes an address straight to its company's only connection" do
    post sso_discovery_path, params: { email: "someone@oidc-acme.test" }

    assert_redirected_to oidc_start_path(id: @provider.id)
  end

  test "SSO discovery offers a choice when a company has several connections" do
    second = create(:identity_provider, company: @company, kind: "oidc", name: "Acme Legacy SSO",
                                        config: { "issuer" => "https://old.example.test", "client_id" => "c2" })
    create(:company_auth_policy, company: @company, identity_provider: second, enabled: true)

    post sso_discovery_path, params: { email: "someone@oidc-acme.test" }

    assert_response :success
    assert_match "Acme Legacy SSO", response.body
  end

  test "SSO discovery for a domain with no connection says so instead of guessing" do
    post sso_discovery_path, params: { email: "someone@unknown-domain-#{SecureRandom.hex(3)}.test" }

    assert_response :redirect
    assert_match(/no_sso_connection/, response.location)
  end

  test "a disabled connection is not offered by discovery" do
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @provider).update!(enabled: false)

    post sso_discovery_path, params: { email: "someone@oidc-acme.test" }

    assert_match(/no_sso_connection/, response.location)
  end

  test "an OIDC sign-in appends its proof to a live session instead of replacing it" do
    member = create(:user, :onboarding_completed, company: @company, email: "person@oidc-acme.test",
                           password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    create(:user_identity, user: member, identity_provider: @provider, subject: "oidc-subject-1")
    sign_in_as(member)
    user_session = UserSession.live.find_by(user: member)

    state, nonce = start_and_capture_state
    build_token_stub(nonce)
    get oidc_callback_path(code: "the-code", state: state)

    assert_equal 1, UserSession.live.where(user: member).count
    assert_includes user_session.reload.proved_provider_ids, @provider.id
    assert_includes user_session.proved_provider_ids, IdentityProvider.password.id
  end
end
