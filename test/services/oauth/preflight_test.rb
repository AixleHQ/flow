# frozen_string_literal: true

require "test_helper"

module Oauth
  class PreflightTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @client = OauthClient.create!(
        issuer: "https://provider.test",
        authorization_endpoint: "https://provider.test/oauth/authorize",
        token_endpoint: "https://provider.test/oauth/token",
        client_id: "c1", source: "static"
      )
    end

    def oauth_server(scope: :per_user)
      create(:mcp_server, :custom, scope: @project, transport: :sse,
             auth_type: :oauth, credential_scope: scope)
    end

    def credential_for(server, owner:, **overrides)
      OauthCredential.create!({
        owner: owner, oauth_client: @client, mcp_server: server, provider: "mcp:x",
        status: :active, access_token: "tok", expires_at: 1.hour.from_now
      }.merge(overrides))
    end

    test "non-oauth servers are never flagged" do
      server = create(:mcp_server, :custom, scope: @project, transport: :sse)
      assert_empty Oauth::Preflight.missing_connections([ server ], user: @user)
    end

    test "flags a per_user server the viewer has not connected" do
      server = oauth_server

      result = Oauth::Preflight.missing_connections([ server ], user: @user)

      assert_equal 1, result.size
      assert_equal server.id, result.first[:mcp_server_id]
      assert_equal "/oauth/mcp/#{server.id}/connect", result.first[:connect_url]
    end

    test "does not flag a per_user server the viewer has connected" do
      server = oauth_server
      credential_for(server, owner: @user)

      assert_empty Oauth::Preflight.missing_connections([ server ], user: @user)
    end

    test "flags a per_user server connected by a DIFFERENT user" do
      server = oauth_server
      other = create(:user, company: @company)
      credential_for(server, owner: other)

      assert_equal 1, Oauth::Preflight.missing_connections([ server ], user: @user).size
    end

    test "flags an errored credential even when it exists" do
      server = oauth_server
      credential_for(server, owner: @user, status: :error)

      assert_equal 1, Oauth::Preflight.missing_connections([ server ], user: @user).size
    end

    test "flags an expired credential with no refresh token (unrefreshable)" do
      server = oauth_server
      credential_for(server, owner: @user, expires_at: 1.minute.ago, refresh_token: nil)

      assert_equal 1, Oauth::Preflight.missing_connections([ server ], user: @user).size
    end

    test "does not flag an expired credential that can still be refreshed" do
      server = oauth_server
      credential_for(server, owner: @user, expires_at: 1.minute.ago, refresh_token: "r1")

      assert_empty Oauth::Preflight.missing_connections([ server ], user: @user)
    end

    test "shared server resolves the credential against the server scope, not the viewer" do
      server = oauth_server(scope: :shared)
      credential_for(server, owner: @project) # owned by the scope

      assert_empty Oauth::Preflight.missing_connections([ server ], user: @user)
    end
  end
end
