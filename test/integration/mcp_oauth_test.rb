# frozen_string_literal: true

require "test_helper"

# Aixle as the OAuth authorization server of its personal MCP server, driven the
# way an MCP client drives it: the 401 challenge, discovery, registration,
# consent, the token exchange, MCP calls with the access token, refresh, and
# disconnecting.
class MCPOauthTest < ActionDispatch::IntegrationTest
  REDIRECT_URI = "cursor://anysphere.cursor-retrieval/oauth/callback"

  setup do
    @company = create(:company, name: "Acme")
    @user = create(:user, :onboarding_completed, company: @company,
                          password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    @verifier = SecureRandom.urlsafe_base64(48)
    @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
    @resource = MCPAuth::Endpoints.resources.first
  end

  def mcp(method, token:, path: "/mcp")
    post path,
         params: { jsonrpc: "2.0", id: 1, method: method, params: {} }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                    "Authorization" => ("Bearer #{token}" if token) }.compact
  end

  def register_client
    post "/mcp-oauth/register", params: { client_name: "Cursor", redirect_uris: [ REDIRECT_URI ],
                                          token_endpoint_auth_method: "client_secret_basic" }.to_json,
                                headers: { "Content-Type" => "application/json" }
    response.parsed_body
  end

  def authorize_params(client_id, **overrides)
    { response_type: "code", client_id: client_id, redirect_uri: REDIRECT_URI, code_challenge: @challenge,
      code_challenge_method: "S256", state: "st-1", scope: "mcp", resource: @resource }.merge(overrides)
  end

  def redirect_params
    Rack::Utils.parse_query(URI.parse(response.location).query)
  end

  def connect(client_id)
    sign_in_as(@user)
    post mcp_oauth_authorize_path, params: authorize_params(client_id, decision: "allow")
    code = redirect_params.fetch("code")
    post "/mcp-oauth/token", params: { grant_type: "authorization_code", code: code, redirect_uri: REDIRECT_URI,
                                       client_id: client_id, code_verifier: @verifier }
    assert_response :ok
    response.parsed_body
  end

  test "an MCP call without a token is told where to sign in" do
    mcp("tools/list", token: nil)

    assert_response :unauthorized
    challenge = response.headers["WWW-Authenticate"]
    metadata_url = challenge[/resource_metadata="([^"]+)"/, 1]
    assert_equal "#{MCPAuth::Endpoints.origin(@resource)}/.well-known/oauth-protected-resource/mcp", metadata_url

    get URI(metadata_url).path
    assert_equal @resource, response.parsed_body["resource"]
    issuer = response.parsed_body["authorization_servers"].first

    get "/.well-known/oauth-authorization-server"
    metadata = response.parsed_body
    assert_equal issuer, metadata["issuer"]
    assert_equal true, metadata["client_id_metadata_document_supported"] # rubocop:disable Minitest/AssertTruthy
    assert_equal [ "none" ], metadata["token_endpoint_auth_methods_supported"]
    assert_equal [ "S256" ], metadata["code_challenge_methods_supported"]
    assert_equal "#{issuer}/mcp-oauth/token", metadata["token_endpoint"]
  end

  test "the agent containers' path has its own resource document" do
    get "/.well-known/oauth-protected-resource/action_mcp"
    assert_equal "#{MCPAuth::Endpoints.origin(@resource)}/action_mcp", response.parsed_body["resource"]

    get "/.well-known/oauth-protected-resource/elsewhere"
    assert_response :not_found
  end

  test "a registered client connects, calls tools as the person, refreshes, and is disconnected" do
    client = register_client
    assert_response :created
    assert_equal "none", client["token_endpoint_auth_method"]

    sign_in_as(@user)
    get mcp_oauth_authorize_path(authorize_params(client["client_id"]))
    assert_inertia_page "Integrations/McpAuthorize"
    assert_inertia_props do |props|
      assert_equal "ready", props[:state]
      assert_equal "Cursor", props[:client][:label]
      assert_equal false, props[:client][:verified] # rubocop:disable Minitest/RefuteFalse
      assert_equal [ "Acme" ], props[:companies]
      assert_equal "an app on this computer (cursor:)", props[:destination]
    end

    tokens = connect(client["client_id"])
    assert_equal "Bearer", tokens["token_type"]
    assert_equal 3600, tokens["expires_in"]

    post "/mcp", params: { jsonrpc: "2.0", id: 2, method: "tools/call",
                           params: { name: "list_companies", arguments: {} } }.to_json,
                 headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                            "Authorization" => "Bearer #{tokens['access_token']}" }
    assert_response :success
    companies = JSON.parse(response.parsed_body.dig("result", "content", 0, "text"))["companies"]
    assert_equal [ @company.id ], companies.map { |c| c["id"] }

    post "/mcp-oauth/token", params: { grant_type: "refresh_token", refresh_token: tokens["refresh_token"],
                                       client_id: client["client_id"] }
    assert_response :ok
    refreshed = response.parsed_body
    assert_not_equal tokens["refresh_token"], refreshed["refresh_token"]

    grant = @user.mcp_auth_grants.active.sole
    get mcp_profile_path
    assert_inertia_props { |props| assert_equal [ grant.id ], props[:mcp][:apps].pluck(:id) }

    delete profile_mcp_app_path(grant)
    assert_redirected_to mcp_profile_path

    mcp("tools/list", token: refreshed["access_token"])
    assert_response :unauthorized
    assert_match(/error="invalid_token"/, response.headers["WWW-Authenticate"])
  end

  test "a code works once, and a second use ends what the first bought" do
    client = register_client
    sign_in_as(@user)
    post mcp_oauth_authorize_path, params: authorize_params(client["client_id"], decision: "allow")
    code = redirect_params.fetch("code")
    exchange = { grant_type: "authorization_code", code: code, redirect_uri: REDIRECT_URI,
                 client_id: client["client_id"], code_verifier: @verifier }

    post "/mcp-oauth/token", params: exchange
    access = response.parsed_body["access_token"]
    post "/mcp-oauth/token", params: exchange

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
    mcp("tools/list", token: access)
    assert_response :unauthorized
  end

  test "the code_verifier must match the challenge" do
    client = register_client
    sign_in_as(@user)
    post mcp_oauth_authorize_path, params: authorize_params(client["client_id"], decision: "allow")

    post "/mcp-oauth/token", params: { grant_type: "authorization_code", code: redirect_params.fetch("code"),
                                       client_id: client["client_id"], code_verifier: "x" * 43 }

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "the consent answers the client with its state and our issuer" do
    client = register_client
    sign_in_as(@user)

    post mcp_oauth_authorize_path, params: authorize_params(client["client_id"], decision: "allow")
    assert response.location.start_with?("cursor://anysphere.cursor-retrieval/oauth/callback?")
    assert_equal "st-1", redirect_params["state"]
    assert_equal MCPAuth::Endpoints.issuer, redirect_params["iss"]

    post mcp_oauth_authorize_path, params: authorize_params(client["client_id"], decision: "deny")
    assert_equal "access_denied", redirect_params["error"]
    assert_equal 1, MCPAuthGrant.count
  end

  test "disabling MCP access ends every connected app along with the token" do
    tokens = connect(register_client["client_id"])
    @user.regenerate_mcp_token!

    delete disable_mcp_token_profile_path

    mcp("tools/list", token: tokens["access_token"])
    assert_response :unauthorized
    post "/mcp-oauth/token", params: { grant_type: "refresh_token", refresh_token: tokens["refresh_token"] }
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "signing out everywhere else ends connected apps too" do
    tokens = connect(register_client["client_id"])

    delete sign_out_other_sessions_profile_path

    mcp("tools/list", token: tokens["access_token"])
    assert_response :unauthorized
  end

  test "revoking a token at the revocation endpoint disconnects the app" do
    client = register_client
    tokens = connect(client["client_id"])

    post "/mcp-oauth/revoke", params: { token: tokens["refresh_token"], client_id: client["client_id"] }
    assert_response :ok

    mcp("tools/list", token: tokens["access_token"])
    assert_response :unauthorized
  end

  test "registration refuses a redirect URI a browser would run" do
    post "/mcp-oauth/register", params: { redirect_uris: [ "javascript:alert(1)" ] }.to_json,
                                headers: { "Content-Type" => "application/json" }

    assert_response :bad_request
    assert_equal "invalid_redirect_uri", response.parsed_body["error"]

    post "/mcp-oauth/register", params: { redirect_uris: [ "http://evil.example/callback" ] }.to_json,
                                headers: { "Content-Type" => "application/json" }
    assert_response :bad_request
  end

  test "an agent container's session key is not challenged to sign in" do
    post "/action_mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
                        headers: { "Content-Type" => "application/json", "X-Session-Key" => "no-such-session" }

    assert_response :unauthorized
    assert_nil response.headers["WWW-Authenticate"]
  end
end
