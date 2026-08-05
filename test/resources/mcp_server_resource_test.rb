# frozen_string_literal: true

require "test_helper"

class MCPServerResourceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @client = OauthClient.create!(
      issuer: "https://sentry.io",
      authorization_endpoint: "https://sentry.io/oauth/authorize/",
      token_endpoint: "https://sentry.io/oauth/token/",
      client_id: "client-123",
      source: "static"
    )
  end

  test "masks header and env VALUES but keeps the keys" do
    server = create(:mcp_server, scope: @project, kind: :custom, transport: :sse,
                    headers: { "Authorization" => "super-secret" }, env: { "TOKEN" => "abc" })

    # Alba serializes top-level keys as camelCase; header/env VALUE keys are preserved verbatim.
    hash = MCPServerResource.new(server).to_h

    assert_equal({ "Authorization" => "••••••" }, hash["headers"])
    assert_equal({ "TOKEN" => "••••••" }, hash["env"])
  end

  test "per_user oauth_status reads the CURRENT viewer's credential" do
    server = create(:mcp_server, scope: @project, kind: :custom, transport: :sse,
                    auth_type: :oauth, credential_scope: :per_user)
    OauthCredential.create!(
      owner: @user, oauth_client: @client, mcp_server: server, provider: "mcp:sentry",
      status: :active, access_token: "tok", expires_at: 2.hours.from_now
    )

    # With the viewer supplied, their active credential surfaces as "active".
    with_user = MCPServerResource.new(server, params: { user: @user }).to_h
    assert_equal "active", with_user["oauthStatus"]

    # A different member has no credential of their own → "pending".
    other = create(:user, company: @company)
    without = MCPServerResource.new(server, params: { user: other }).to_h
    assert_equal "pending", without["oauthStatus"]
  end

  test "oauth_status is nil for non-oauth servers" do
    server = create(:mcp_server, scope: @project, kind: :custom, transport: :sse)
    hash = MCPServerResource.new(server, params: { user: @user }).to_h
    assert_nil hash["oauthStatus"]
  end

  # The install form edits one line, so the resource sends one line — regardless of
  # whether the row was typed in or rendered by a catalog install, which stores the
  # executable and its argv apart.
  test "command is the whole launch line, not just the executable" do
    server = create(:mcp_server, :stdio_transport, scope: @project, kind: :custom,
                    command: "npx", args: [ "-y", "remote-filesystem-mcp-server@0.1.2" ])

    assert_equal "npx -y remote-filesystem-mcp-server@0.1.2",
                 MCPServerResource.new(server, params: { user: @user }).to_h["command"]
  end

  test "command is null for a server with no launch line at all" do
    server = create(:mcp_server, scope: @project, kind: :custom, transport: :sse)

    assert_nil MCPServerResource.new(server, params: { user: @user }).to_h["command"]
  end
end
