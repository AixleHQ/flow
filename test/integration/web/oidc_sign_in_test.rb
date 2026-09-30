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
    resolve_hosts_publicly!

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

  test "a callback opened in a browser that did not start the flow is refused" do
    state, nonce = start_and_capture_state
    build_token_stub(nonce)
    elsewhere = open_session

    assert_no_difference "User.count" do
      elsewhere.get oidc_callback_path(code: "the-code", state: state)
    end

    assert_equal login_path(error: "oauth_failed"), URI.parse(elsewhere.response.location).request_uri
    assert_not_requested :post, "#{ISSUER}/token"

    # Refusing it burned nothing: the browser that began the flow still finishes.
    get oidc_callback_path(code: "the-code", state: state)

    assert_redirected_to company_projects_path
    assert UserSession.live.exists?(user: User.find_by(email: "person@oidc-acme.test"))
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

    assert_redirected_to company_settings_access_path
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

  # Asserting the redirect TARGET was what hid the bug: /auth/oidc/:id/start is
  # POST only, a redirect is followed with GET, and the browser landed on a
  # routing error. What matters is that discovery reaches the provider.
  test "an address resolves straight to its company's only connection" do
    post login_identify_path, params: { email: "someone@oidc-acme.test" }

    assert_response :redirect
    assert_match ISSUER, response.location
    assert_match(/state=/, response.location)
  end

  # The shape of the old bug: discovery answered with a path of our own that
  # only accepts POST, and the browser followed it with GET. Leaving for the
  # provider is the only correct answer here.
  test "resolving leaves this app rather than pointing at one of its own routes" do
    post login_identify_path, params: { email: "someone@oidc-acme.test" }

    assert_match %r{\Ahttps://}, response.location
    assert_not_equal URI.parse(response.location).host, URI.parse(root_url).host
  end

  test "an address offers a choice when its company has several connections" do
    second = create(:identity_provider, company: @company, kind: "oidc", name: "Acme Legacy SSO",
                                        config: { "issuer" => "https://old.example.test", "client_id" => "c2" })
    create(:company_auth_policy, company: @company, identity_provider: second, enabled: true)

    post login_identify_path, params: { email: "someone@oidc-acme.test" }

    assert_response :success
    assert_match "Acme Legacy SSO", response.body
  end

  # The mode is pinned rather than inherited: config/settings/test.yml reads
  # DEPLOYMENT_MODE from the environment, so a developer who set it for a local
  # stack would otherwise get a different answer here than CI does.
  # Registration off is the other half of the same gate: with it closed, a hosted
  # installation answers exactly as a self-hosted one does.
  test "an unclaimed domain is a refusal again once registration is off" do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    Settings.stubs(:registration).returns(Hashie::Mash.new(enabled: false))

    post login_identify_path, params: { email: "someone@unknown-domain-#{SecureRandom.hex(3)}.test" }

    assert_redirected_to login_path(error: "no_workspace")
  end

  test "an address no workspace claims is told so, rather than shown a password box" do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SELF_HOSTED))

    post login_identify_path, params: { email: "someone@unknown-domain-#{SecureRandom.hex(3)}.test" }

    assert_response :redirect
    assert_match(/no_workspace/, response.location)
  end

  # Where anyone may sign a company up, that same address is not a refusal: it is
  # the first field of a signup. Answering it with "contact your admin" turned
  # the one door away from the product.
  test "where we host, an unclaimed domain starts a signup instead" do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    Settings.stubs(:registration).returns(Hashie::Mash.new(enabled: true))
    email = "someone@unknown-domain-#{SecureRandom.hex(3)}.test"

    post login_identify_path, params: { email: email }

    assert_redirected_to new_workspace_path(email: email)
  end

  test "a disabled connection is not offered, and the workspace's other methods are" do
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @provider).update!(enabled: false)

    post login_identify_path, params: { email: "someone@oidc-acme.test" }

    assert_response :success
    assert_equal "credentials", inertia.props[:step]
    assert_not_includes inertia.props[:methods], "oidc"
  end

  # The whole point of branching on the domain. An address nobody has ever used
  # must answer exactly as a known one does — otherwise this screen tells a
  # stranger which addresses are registered.
  test "an unknown address at a known domain answers exactly as a known one" do
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @provider).update!(enabled: false)

    post login_identify_path, params: { email: "definitely-nobody-#{SecureRandom.hex(4)}@oidc-acme.test" }
    stranger = [ response.status, inertia.props[:step], inertia.props[:methods], inertia.props[:companyName] ]

    post login_identify_path, params: { email: "someone@oidc-acme.test" }
    known = [ response.status, inertia.props[:step], inertia.props[:methods], inertia.props[:companyName] ]

    assert_equal known, stranger
  end

  test "authentication codes are never offered as a way in" do
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @provider).update!(enabled: false)
    totp = IdentityProvider.deployment!("totp")
    CompanyAuthPolicy.find_or_create_by!(company: @company, identity_provider: totp) { |p| p.enabled = true }

    post login_identify_path, params: { email: "someone@oidc-acme.test" }

    assert_not_includes inertia.props[:methods], "totp",
      "a six-digit code confirms a session; there is nobody to look up from it"
  end

  test "an issuer that cannot be reached ends the start as a failed sign-in" do
    stub_request(:get, "#{ISSUER}/.well-known/openid-configuration").to_raise(Errno::ECONNREFUSED)

    post oidc_start_path(id: @provider.id)

    assert_redirected_to login_path(error: "oauth_failed")
  end

  test "an issuer that now resolves internally is not dialed and ends as a failed sign-in" do
    UrlSafetyValidator.stubs(:resolved_addresses).with("idp.example.test").returns([ IPAddr.new("10.0.0.5") ])

    post oidc_start_path(id: @provider.id)

    assert_redirected_to login_path(error: "oauth_failed")
    assert_not_requested :get, "#{ISSUER}/.well-known/openid-configuration"
  end

  test "a token endpoint that cannot be reached ends the callback as a failed sign-in" do
    state, = start_and_capture_state
    stub_request(:post, "#{ISSUER}/token").to_timeout

    get oidc_callback_path(code: "the-code", state: state)

    assert_redirected_to login_path(error: "oauth_failed")
  end

  test "an address that is not an address goes back rather than resolving" do
    post login_identify_path, params: { email: "not-an-address" }

    assert_response :redirect
    assert_match(/invalid_email/, response.location)
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
