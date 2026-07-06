# frozen_string_literal: true

require "test_helper"

# Request test for the unified OAuth 2.1 flow engine
# (GET /oauth/:provider/authorize and GET /oauth/callback -> Web::OauthController).
#
# This test is SECURITY-focused. It exercises the real State machinery
# (Oauth::State.encode/decode/consume round-tripped through Rails.cache) and the
# real Oauth::Providers reconciliation; only two boundaries are faked:
#   * Rails.cache -> a live MemoryStore (test env is :null_store, which would make
#     every nonce look already-consumed), exactly as the Slack OAuth test does.
#   * the provider token endpoint -> WebMock, so no network call leaves the box.
#
# Depends on Builder A's OauthClient/OauthCredential models + migrations and the
# oauth_key/sentry_oauth Settings keys.
class Web::OauthControllerTest < ActionDispatch::IntegrationTest
  TOKEN_ENDPOINT = "https://sentry.io/oauth/token/"
  AUTHORIZE_HOST = "sentry.io"

  setup do
    # Real cache so an encoded state's nonce survives to #consume.
    @cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(@cache)

    # Operator-set provider credentials (normally Settings.sentry_oauth) — stubbed
    # so client_for can reconcile an OauthClient without live secrets.
    Settings.stubs(:sentry_oauth).returns(
      OpenStruct.new(client_id: "sentry-cid", client_secret: "sentry-secret")
    )

    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)

    stub_token_success!
  end

  # --- helpers -------------------------------------------------------------

  def stub_token_success!
    stub_request(:post, TOKEN_ENDPOINT).to_return(
      status: 200,
      body: {
        access_token: "at-live-001", refresh_token: "rt-live-001",
        token_type: "Bearer", expires_in: 3600, scope: "org:read"
      }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  # Encode a real state (side-effects the nonce into the stubbed cache) so the
  # callback can be driven exactly as the browser would return.
  def build_state(owner:, user: @user, provider: "sentry", return_to: "/company/projects", mcp_server_id: nil, code_verifier: "pkce-verifier-001")
    Oauth::State.encode(
      owner_type: owner.class.name, owner_id: owner.id, user_id: user.id,
      provider: provider, return_to: return_to, mcp_server_id: mcp_server_id,
      code_verifier: code_verifier
    )
  end

  def query_params(location)
    URI.decode_www_form(URI(location).query.to_s).to_h
  end

  # --- AUTHORIZE -----------------------------------------------------------

  test "authorize redirects to the provider with mandatory PKCE (S256) and no verifier in the URL" do
    get oauth_authorize_path("sentry"), params: { owner_type: "Company", owner_id: @company.id, return_to: "/company/projects" }

    assert_response :redirect
    location = @response.headers["Location"]
    assert_equal AUTHORIZE_HOST, URI(location).host

    q = query_params(location)
    assert_equal "code", q["response_type"]
    assert_equal "sentry-cid", q["client_id"]
    assert_equal "S256", q["code_challenge_method"]
    assert q["code_challenge"].present?, "a PKCE challenge must be sent"
    assert q["redirect_uri"].end_with?("/oauth/callback"), "single deployment-wide redirect URI"
    assert q["state"].present?
    refute q.key?("code_verifier"), "the PKCE code_verifier must NEVER appear in the URL"
  end

  test "authorize sanitizes an open-redirect return_to before signing it into the state" do
    get oauth_authorize_path("sentry"), params: { owner_type: "Company", owner_id: @company.id, return_to: "//evil.com/steal" }

    assert_response :redirect
    signed = query_params(@response.headers["Location"])["state"]
    assert_equal "/", Oauth::State.decode(signed)["return_to"], "protocol-relative return_to must be neutralized"
  end

  test "authorize neutralizes a control-char return_to (browsers strip Tab/CR/LF into a protocol-relative redirect)" do
    get oauth_authorize_path("sentry"), params: { owner_type: "Company", owner_id: @company.id, return_to: "/\t/evil.com" }

    assert_response :redirect
    signed = query_params(@response.headers["Location"])["state"]
    assert_equal "/", Oauth::State.decode(signed)["return_to"], "control-char return_to must be neutralized"
  end

  test "authorize rejects an unknown provider" do
    get oauth_authorize_path("github"), params: { owner_type: "Company", owner_id: @company.id }
    assert_redirected_to root_path
    assert_equal "Unknown OAuth provider", flash[:alert]
  end

  test "authorize refuses an owner the user may not act for" do
    other = create(:company)
    get oauth_authorize_path("sentry"), params: { owner_type: "Company", owner_id: other.id }
    assert_redirected_to root_path
    assert_equal "Not permitted", flash[:alert]
  end

  # --- CALLBACK: happy path ------------------------------------------------

  test "callback exchanges the code (with PKCE verifier), persists the credential, and redirects" do
    state = build_state(owner: @company, return_to: "/company/projects")

    assert_difference("OauthCredential.count", 1) do
      get oauth_callback_path, params: { code: "auth-code-1", state: state }
    end

    assert_redirected_to "/company/projects"
    assert_equal "Connected", flash[:notice]

    # The verifier held server-side was sent on the exchange, not from the URL.
    assert_requested(:post, TOKEN_ENDPOINT) do |req|
      body = URI.decode_www_form(req.body).to_h
      body["grant_type"] == "authorization_code" &&
        body["code"] == "auth-code-1" &&
        body["code_verifier"] == "pkce-verifier-001" &&
        body["client_id"] == "sentry-cid"
    end

    cred = OauthCredential.last
    assert_equal @company, cred.owner
    assert_equal "sentry", cred.provider
    assert_equal "at-live-001", cred.access_token
    assert cred.active?
  end

  # --- CALLBACK: security guards ------------------------------------------

  test "replay is rejected: the single-use nonce is consumed on first use" do
    state = build_state(owner: @company)

    get oauth_callback_path, params: { code: "auth-code-1", state: state }
    assert_equal 1, OauthCredential.count

    assert_no_difference("OauthCredential.count") do
      get oauth_callback_path, params: { code: "auth-code-1", state: state }
    end
    assert_equal "This authorization link was already used", flash[:alert]
  end

  test "an expired state is rejected and exchanges nothing" do
    state = build_state(owner: @company)

    travel(Oauth::State::TTL + 1.minute) do
      assert_no_difference("OauthCredential.count") do
        get oauth_callback_path, params: { code: "auth-code-1", state: state }
      end
    end

    assert_redirected_to root_path
    assert_equal "Invalid or expired authorization", flash[:alert]
    assert_not_requested(:post, TOKEN_ENDPOINT)
  end

  test "a tampered / garbage state is rejected" do
    assert_no_difference("OauthCredential.count") do
      get oauth_callback_path, params: { code: "auth-code-1", state: "not-a-real-state" }
    end
    assert_redirected_to root_path
    assert_equal "Invalid or expired authorization", flash[:alert]
    assert_not_requested(:post, TOKEN_ENDPOINT)
  end

  test "a state pinned to a different user is rejected (anti-CSRF, double pin)" do
    other_user = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    state = build_state(owner: @company, user: other_user)

    assert_no_difference("OauthCredential.count") do
      get oauth_callback_path, params: { code: "auth-code-1", state: state }
    end
    assert_redirected_to root_path
    assert_equal "Authorization did not match your session", flash[:alert]
    assert_not_requested(:post, TOKEN_ENDPOINT)
  end

  test "an open-redirect return_to is neutralized on the callback too (cancel branch)" do
    state = build_state(owner: @company, return_to: "//evil.com/steal")

    get oauth_callback_path, params: { state: state, error: "access_denied" }

    assert_redirected_to root_path, "must not honor a cross-site return_to"
    assert_equal "Connection was cancelled", flash[:alert]
    assert_not_requested(:post, TOKEN_ENDPOINT)
  end

  test "cancel does NOT consume the nonce: the user can retry within the TTL" do
    state = build_state(owner: @company, return_to: "/company/projects")

    get oauth_callback_path, params: { state: state, error: "access_denied" }
    assert_equal "Connection was cancelled", flash[:alert]
    assert_equal 0, OauthCredential.count

    # Same state, this time completing — the nonce was preserved by the cancel.
    assert_difference("OauthCredential.count", 1) do
      get oauth_callback_path, params: { code: "auth-code-1", state: state }
    end
    assert_equal "Connected", flash[:notice]
  end

  test "callback refuses an owner the user may not act for" do
    other = create(:company)
    state = build_state(owner: other)

    assert_no_difference("OauthCredential.count") do
      get oauth_callback_path, params: { code: "auth-code-1", state: state }
    end
    assert_redirected_to root_path
    assert_equal "Not permitted", flash[:alert]
    assert_not_requested(:post, TOKEN_ENDPOINT)
  end

  test "a failed token exchange yields a generic error and never leaks token material" do
    stub_request(:post, TOKEN_ENDPOINT).to_return(status: 400, body: "invalid_grant")
    state = build_state(owner: @company, return_to: "/company/projects")

    assert_no_difference("OauthCredential.count") do
      get oauth_callback_path, params: { code: "auth-code-1", state: state }
    end

    assert_redirected_to "/company/projects"
    assert_equal "Failed to complete connection", flash[:alert]
  end

  test "unauthenticated users are bounced to login" do
    delete logout_path
    state = build_state(owner: @company)
    get oauth_callback_path, params: { code: "auth-code-1", state: state }
    assert_redirected_to login_path
  end
end
