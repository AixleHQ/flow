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
  def build_state(owner:, user: @user, provider: "sentry", return_to: "/company/projects",
                  mcp_server_id: nil, code_verifier: "pkce-verifier-001", resource: nil, oauth_client_id: nil)
    Oauth::State.encode(
      owner_type: owner.class.name, owner_id: owner.id, user_id: user.id,
      provider: provider, return_to: return_to, mcp_server_id: mcp_server_id,
      code_verifier: code_verifier, resource: resource, oauth_client_id: oauth_client_id
    )
  end

  # A persisted DCR (dynamic client registration) client — the kind Phase-3
  # discovery produces and the mcp_connect / callback flow consumes.
  def build_dcr_client(issuer: "https://auth.mcp.test", client_id: "dcr-cid", scopes: "mcp:read")
    OauthClient.create!(
      issuer: issuer, client_id: client_id, source: "dcr", scopes: scopes,
      authorization_endpoint: "#{issuer}/authorize", token_endpoint: "#{issuer}/token"
    )
  end

  def stub_mcp_token_success!(endpoint)
    stub_request(:post, endpoint).to_return(
      status: 200,
      body: { access_token: "mcp-at-1", refresh_token: "mcp-rt-1",
              token_type: "Bearer", expires_in: 3600, scope: "mcp:read" }.to_json,
      headers: { "Content-Type" => "application/json" }
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

  # --- MCP CONNECT: discovery + DCR, then consent --------------------------
  # Depends on the DISCOVERY builder's MCP::OauthDiscoveryService / MCP::DiscoveryError
  # (pinned interface); prepare is stubbed so no discovery network call is made here.

  def stub_discovery!(client:, resource: "https://mcp.acme.test/v1", scopes: "mcp:read")
    result = OpenStruct.new(oauth_client: client, resource: resource, scopes: scopes)
    MCP::OauthDiscoveryService.stubs(:prepare).returns(result)
    result
  end

  test "mcp_connect discovers the client and redirects to consent with PKCE + RFC 8707 resource" do
    server = create(:mcp_server, :custom, scope: @project, auth_type: :oauth, credential_scope: :shared,
                    url: "https://mcp.acme.test/v1")
    client = build_dcr_client
    stub_discovery!(client: client)

    get oauth_mcp_connect_path(mcp_server_id: server.id), params: { return_to: "/company/projects" }

    assert_response :redirect
    location = @response.headers["Location"]
    assert_equal "auth.mcp.test", URI(location).host

    q = query_params(location)
    assert_equal "code", q["response_type"]
    assert_equal "dcr-cid", q["client_id"]
    assert_equal "S256", q["code_challenge_method"]
    assert q["code_challenge"].present?, "a PKCE challenge must be sent"
    assert_equal "https://mcp.acme.test/v1", q["resource"], "RFC 8707 resource indicator on authorize"
    assert_equal "mcp:read", q["scope"]
    refute q.key?("code_verifier"), "the PKCE verifier must NEVER appear in the URL"

    payload = Oauth::State.decode(q["state"])
    assert_equal "mcp:mcp.acme.test", payload["provider"]
    assert_equal "https://mcp.acme.test/v1", payload["resource"]
    assert_equal client.id, payload["oauth_client_id"]
    assert_equal "Project", payload["owner_type"]
    assert_equal @project.id, payload["owner_id"]
  end

  # Regression: Railway's discovered authorization_endpoint is
  # ".../oauth/auth?resource=https%3A%2F%2Fbackboard.railway.com". Appending a
  # second "?" folded `response_type=code` into that `resource` value, so Railway
  # answered `error=invalid_request` / "missing required parameter 'response_type'".
  test "mcp_connect merges its parameters into an authorization_endpoint that already carries a query" do
    server = create(:mcp_server, :custom, scope: @project, auth_type: :oauth, credential_scope: :shared,
                    url: "https://mcp.acme.test/v1")
    client = build_dcr_client
    client.update!(authorization_endpoint: "https://auth.mcp.test/authorize?resource=https%3A%2F%2Fauth.mcp.test&prompt=consent")
    stub_discovery!(client: client)

    get oauth_mcp_connect_path(mcp_server_id: server.id)

    assert_response :redirect
    location = @response.headers["Location"]
    assert_equal 1, location.count("?"), "a second '?' folds our first parameter into the endpoint's own value"

    pairs = URI.decode_www_form(URI(location).query.to_s)
    assert_equal "code", pairs.to_h["response_type"]
    assert_equal "consent", pairs.to_h["prompt"], "the endpoint's own parameters survive the merge"
    assert_equal [ "https://mcp.acme.test/v1" ], pairs.select { |k, _| k == "resource" }.map(&:last),
                 "exactly one RFC 8707 resource indicator, naming the MCP server and not the auth server"
  end

  test "mcp_connect omits scope entirely when neither discovery nor the client advertises one" do
    server = create(:mcp_server, :custom, scope: @project, auth_type: :oauth, url: "https://mcp.acme.test/v1")
    stub_discovery!(client: build_dcr_client(scopes: nil), scopes: nil)

    get oauth_mcp_connect_path(mcp_server_id: server.id)

    q = query_params(@response.headers["Location"])
    refute q.key?("scope"), "an empty scope= is a request error at some authorization servers"
  end

  test "mcp_connect tells the user WHY discovery failed when the failure is diagnosable" do
    server = create(:mcp_server, :custom, scope: @project, auth_type: :oauth, url: "https://mcp.acme.test/v1")
    error = MCP::RegistrationError.new("unexpected status=400", code: "invalid_redirect_uri")
    MCP::OauthDiscoveryService.stubs(:prepare).raises(error)

    get oauth_mcp_connect_path(mcp_server_id: server.id), params: { return_to: "/company/projects" }

    assert_redirected_to "/company/projects"
    assert_equal error.user_message, flash[:alert]
    assert_match(/operator/, flash[:alert])
  end

  test "mcp_connect stays vague when the failure really is a connection problem" do
    server = create(:mcp_server, :custom, scope: @project, auth_type: :oauth, url: "https://mcp.acme.test/v1")
    MCP::OauthDiscoveryService.stubs(:prepare).raises(MCP::DiscoveryError, "connection reset")

    get oauth_mcp_connect_path(mcp_server_id: server.id)

    assert_equal MCP::DiscoveryError::GENERIC, flash[:alert]
    assert_no_match(/connection reset/, flash[:alert], "an exception message is not a user message")
  end

  test "mcp_connect pins the connecting identity to the current user for a per_user server" do
    server = create(:mcp_server, :custom, scope: @project, auth_type: :oauth, credential_scope: :per_user,
                    url: "https://mcp.acme.test/v1")
    stub_discovery!(client: build_dcr_client)

    get oauth_mcp_connect_path(mcp_server_id: server.id)

    payload = Oauth::State.decode(query_params(@response.headers["Location"])["state"])
    assert_equal "User", payload["owner_type"]
    assert_equal @user.id, payload["owner_id"]
  end

  test "mcp_connect refuses a non-oauth server (never runs discovery)" do
    server = create(:mcp_server, :custom, scope: @project) # auth_type :none
    MCP::OauthDiscoveryService.expects(:prepare).never

    get oauth_mcp_connect_path(mcp_server_id: server.id)
    assert_redirected_to root_path
    assert_equal "Not permitted", flash[:alert]
  end

  test "mcp_connect refuses a server the user may not act for (never runs discovery)" do
    other = create(:company)
    other_project = create(:project, company: other, owner: create(:user, company: other))
    server = create(:mcp_server, :custom, scope: other_project, auth_type: :oauth, url: "https://mcp.other.test/v1")
    MCP::OauthDiscoveryService.expects(:prepare).never

    get oauth_mcp_connect_path(mcp_server_id: server.id)
    assert_redirected_to root_path
    assert_equal "Not permitted", flash[:alert]
  end

  test "mcp_connect surfaces a generic error and leaks no metadata when discovery fails" do
    server = create(:mcp_server, :custom, scope: @project, auth_type: :oauth, url: "https://mcp.acme.test/v1")
    MCP::OauthDiscoveryService.stubs(:prepare).raises(MCP::DiscoveryError.new("boom"))

    get oauth_mcp_connect_path(mcp_server_id: server.id), params: { return_to: "/company/projects" }
    assert_redirected_to "/company/projects"
    assert_equal "Couldn't connect to this MCP server", flash[:alert]
  end

  # --- CALLBACK: MCP (DCR) branch ------------------------------------------

  test "callback (mcp) loads the signed DCR client, threads the resource, and upserts an mcp:<host> credential" do
    server = create(:mcp_server, :custom, scope: @project, auth_type: :oauth, credential_scope: :shared,
                    url: "https://mcp.acme.test/v1")
    client = build_dcr_client
    stub_mcp_token_success!("https://auth.mcp.test/token")

    state = build_state(owner: @company, provider: "mcp:mcp.acme.test", mcp_server_id: server.id,
                        resource: "https://mcp.acme.test/v1", oauth_client_id: client.id,
                        return_to: "/company/projects")

    assert_difference("OauthCredential.count", 1) do
      get oauth_callback_path, params: { code: "mcp-code-1", state: state }
    end

    assert_redirected_to "/company/projects"
    assert_equal "Connected", flash[:notice]

    assert_requested(:post, "https://auth.mcp.test/token") do |req|
      body = URI.decode_www_form(req.body).to_h
      body["grant_type"] == "authorization_code" &&
        body["code"] == "mcp-code-1" &&
        body["code_verifier"] == "pkce-verifier-001" &&
        body["resource"] == "https://mcp.acme.test/v1" && # RFC 8707
        body["client_id"] == "dcr-cid"
    end

    cred = OauthCredential.last
    assert_equal @company, cred.owner
    assert_equal "mcp:mcp.acme.test", cred.provider
    assert_equal server.id, cred.mcp_server_id
    assert_equal client.id, cred.oauth_client_id
    assert_equal "mcp-at-1", cred.access_token
  end

  test "callback (mcp) rejects an oauth_client_id that is not a source:\"dcr\" client" do
    static = OauthClient.create!(issuer: "https://static.test", client_id: "static-cid", source: "static",
                                 authorization_endpoint: "https://static.test/authorize",
                                 token_endpoint: "https://static.test/token")
    state = build_state(owner: @company, provider: "mcp:mcp.acme.test",
                        resource: "https://mcp.acme.test/v1", oauth_client_id: static.id,
                        return_to: "/company/projects")

    assert_no_difference("OauthCredential.count") do
      get oauth_callback_path, params: { code: "mcp-code-1", state: state }
    end
    assert_redirected_to "/company/projects"
    assert_equal "Unknown OAuth client", flash[:alert]
  end

  test "callback (mcp) rejects an unknown oauth_client_id" do
    state = build_state(owner: @company, provider: "mcp:mcp.acme.test",
                        resource: "https://mcp.acme.test/v1", oauth_client_id: 999_999,
                        return_to: "/company/projects")

    get oauth_callback_path, params: { code: "mcp-code-1", state: state }
    assert_redirected_to "/company/projects"
    assert_equal "Unknown OAuth client", flash[:alert]
  end

  # --- CIMD client-metadata document ---------------------------------------

  test "client-metadata.json is publicly fetchable and is a valid CIMD document" do
    # A fresh, unauthenticated session — the AS dereferences this URL with no cookie.
    anon = open_session
    anon.get "/oauth/client-metadata.json"

    assert_equal 200, anon.response.status
    doc = JSON.parse(anon.response.body)

    base = "#{Settings.protocol}://#{Settings.domain}"
    # CIMD invariant: the document's client_id equals the URL it is served at.
    assert_equal "#{base}/oauth/client-metadata.json", doc["client_id"]
    # We identify to the authorization server as the product, "Aixle Flow".
    assert_equal "Aixle Flow", doc["client_name"]
    assert_includes doc["redirect_uris"], "#{base}/oauth/callback"
    assert_equal "none", doc["token_endpoint_auth_method"]
    assert_equal %w[authorization_code refresh_token], doc["grant_types"]
    assert_equal %w[code], doc["response_types"]
  end
end
