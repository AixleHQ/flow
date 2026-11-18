# frozen_string_literal: true

require "test_helper"

# The authorize screen of Aixle's OAuth server for the personal MCP: what it
# refuses on the page, what it sends back to the client, and how it survives a
# sign-in in between.
class Web::MCPAuthorizationsTest < ActionDispatch::IntegrationTest
  CLAUDE_CODE = "https://claude.ai/oauth/claude-code-client-metadata"

  setup do
    @company = create(:company, name: "Acme")
    @user = create(:user, :onboarding_completed, company: @company,
                          password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    @client = MCPAuthClient.register!(client_name: "Cursor", redirect_uris: [ "http://127.0.0.1/callback" ])
    @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest("v" * 43), padding: false)
  end

  def authorize_params(**overrides)
    { response_type: "code", client_id: @client.client_id, redirect_uri: "http://127.0.0.1:5173/callback",
      code_challenge: @challenge, code_challenge_method: "S256", state: "st-1" }.merge(overrides)
  end

  def redirect_params = Rack::Utils.parse_query(URI.parse(response.location).query)

  test "a guest signs in first and comes back to the same authorization" do
    get mcp_oauth_authorize_path(authorize_params)
    assert_redirected_to login_path

    sign_in_as(@user)
    follow_redirect!

    assert_equal "/mcp-oauth/authorize", path
    assert_equal @client.client_id, request.params["client_id"]
    assert_inertia_page "Integrations/McpAuthorize"
    assert_inertia_props { |props| assert_equal "ready", props[:state] }
  end

  test "an unknown client and an unregistered redirect URI are refused on the page, not redirected" do
    sign_in_as(@user)

    get mcp_oauth_authorize_path(authorize_params(client_id: "aocl_nobody"))
    assert_inertia_page "Integrations/McpAuthorize"
    assert_inertia_props do |props|
      assert_equal "invalid", props[:state]
      assert_equal "This app is not registered with Aixle", props[:message]
    end

    get mcp_oauth_authorize_path(authorize_params(redirect_uri: "https://evil.example/callback"))
    assert_inertia_props { |props| assert_match(/did not register/, props[:message]) }

    post mcp_oauth_authorize_path, params: authorize_params(redirect_uri: "https://evil.example/cb", decision: "allow")
    assert_response :success
    assert_equal 0, MCPAuthGrant.count
  end

  test "a request without S256 PKCE goes back to the client as an error" do
    sign_in_as(@user)

    get mcp_oauth_authorize_path(authorize_params(code_challenge_method: "plain"))

    assert_response :redirect
    assert_equal "invalid_request", redirect_params["error"]
    assert_equal "st-1", redirect_params["state"]

    get mcp_oauth_authorize_path(authorize_params(resource: "https://elsewhere.example/mcp"))
    assert_equal "invalid_target", redirect_params["error"]
  end

  test "a client identified by its metadata document is named by its host" do
    resolve_hosts_publicly!
    stub_request(:get, CLAUDE_CODE).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { client_id: CLAUDE_CODE, client_name: "Claude Code",
              redirect_uris: %w[http://localhost/callback http://127.0.0.1/callback],
              token_endpoint_auth_method: "none" }.to_json
    )
    sign_in_as(@user)

    get mcp_oauth_authorize_path(authorize_params(client_id: CLAUDE_CODE, redirect_uri: "http://localhost:3118/callback"))

    assert_inertia_props do |props|
      assert_equal "Claude Code (claude.ai)", props[:client][:label]
      assert_equal true, props[:client][:verified] # rubocop:disable Minitest/AssertTruthy
      assert_equal true, props[:onThisComputer] # rubocop:disable Minitest/AssertTruthy
    end

    post mcp_oauth_authorize_path,
         params: authorize_params(client_id: CLAUDE_CODE, redirect_uri: "http://localhost:3118/callback",
                                  decision: "allow")
    assert response.location.start_with?("http://localhost:3118/callback?code=aoac_")
    grant = MCPAuthGrant.sole
    assert_equal [ "cimd", "Claude Code (claude.ai)" ], [ grant.client_kind, grant.client_name ]
  end

  test "an operator impersonating someone cannot connect an app as them" do
    operator = create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(operator)
    post impersonate_admin_user_path(@user)

    post mcp_oauth_authorize_path, params: authorize_params(decision: "allow")

    assert_inertia_page "Integrations/McpAuthorize"
    assert_inertia_props { |props| assert_equal "impersonating", props[:state] }
    assert_equal 0, MCPAuthGrant.count
  end
end
