# frozen_string_literal: true

require "test_helper"

module Oauth
  # Exercises Oauth::TokenService against the real OauthClient/OauthCredential
  # models (testing doctrine R2: don't mock what you own). Only the provider
  # token endpoint is faked, via WebMock (R4: contract-test the HTTP boundary).
  class TokenServiceTest < ActiveSupport::TestCase
    TOKEN_ENDPOINT = "https://provider.test/oauth/token"

    setup do
      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)

      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @client = build_client
    end

    # == access_token_for: selection / no-op ==

    test "returns nil when no credential is attached to the server" do
      server = create(:mcp_server, :custom, scope: @project)

      assert_nil Oauth::TokenService.access_token_for(server: server, user: @user)
    end

    test "returns nil when no credential exists for owner+provider" do
      assert_nil Oauth::TokenService.access_token_for(owner: @company, provider: "sentry", user: @user)
    end

    # == fresh: token still valid ==

    test "returns the stored token without hitting the network when not near expiry" do
      cred = build_credential(owner: @user, access_token: "valid-token",
                              refresh_token: "r1", expires_at: 1.hour.from_now)

      token = Oauth::TokenService.access_token_for(owner: @user, provider: "sentry", user: @user)

      assert_equal "valid-token", token
      assert_equal cred.id, Oauth::TokenService.pick_credential(server: nil, owner: @user, provider: "sentry", user: @user).id
      assert_not_requested :post, TOKEN_ENDPOINT
    end

    # == fresh: refresh path ==

    test "refreshes under expiry and persists the rotated token pair" do
      cred = build_credential(owner: @user, access_token: "old-token",
                              refresh_token: "old-refresh", expires_at: 1.minute.from_now)
      stub_token_endpoint(access_token: "new-token", refresh_token: "new-refresh", expires_in: 3600)

      token = Oauth::TokenService.access_token_for(owner: @user, provider: "sentry", user: @user)

      assert_equal "new-token", token
      cred.reload
      assert_equal "new-token", cred.access_token
      assert_equal "new-refresh", cred.refresh_token
      assert cred.active?
      assert_not_nil cred.last_refreshed_at
      assert_requested(:post, TOKEN_ENDPOINT) do |req|
        req.body.include?("grant_type=refresh_token") && req.body.include?("refresh_token=old-refresh")
      end
    end

    test "retains the existing refresh token when the refresh response omits one" do
      cred = build_credential(owner: @user, access_token: "old-token",
                              refresh_token: "keep-me", expires_at: 1.minute.from_now)
      stub_token_endpoint(access_token: "new-token", expires_in: 3600) # no refresh_token key

      Oauth::TokenService.access_token_for(owner: @user, provider: "sentry", user: @user)

      assert_equal "keep-me", cred.reload.refresh_token
    end

    test "sends client_secret only for confidential clients" do
      confidential = build_client(client_id: "confidential-client", client_secret: "shh")
      build_credential(owner: @company, oauth_client: confidential, access_token: "old",
                       refresh_token: "r", expires_at: 1.minute.from_now)
      stub_token_endpoint(access_token: "new-token", expires_in: 3600)

      Oauth::TokenService.access_token_for(owner: @company, provider: "sentry", user: @user)

      assert_requested(:post, TOKEN_ENDPOINT) { |req| req.body.include?("client_secret=shh") }
    end

    test "omits client_secret for public (PKCE-only) clients" do
      build_credential(owner: @user, access_token: "old",
                       refresh_token: "r", expires_at: 1.minute.from_now)
      stub_token_endpoint(access_token: "new-token", expires_in: 3600)

      Oauth::TokenService.access_token_for(owner: @user, provider: "sentry", user: @user)

      assert_requested(:post, TOKEN_ENDPOINT) { |req| !req.body.include?("client_secret") }
    end

    # == fresh: reauth-required paths ==

    test "raises ReauthRequired without a network call when the credential is unrefreshable" do
      cred = build_credential(owner: @user, access_token: "old-token",
                              refresh_token: nil, expires_at: 1.minute.ago)

      assert_raises(Oauth::ReauthRequired) do
        Oauth::TokenService.access_token_for(owner: @user, provider: "sentry", user: @user)
      end
      assert_not_requested :post, TOKEN_ENDPOINT
      # Recorded like any other refresh failure: an authorization server that issues no
      # refresh_token (Railway, without consented offline access) otherwise leaves the
      # credential :active with a 0 failure count until its access token lapses.
      assert_equal 1, cred.reload.refresh_failure_count
      assert cred.refresh_error.present?
    end

    test "escalates an unrefreshable credential to error after MAX_REFRESH_FAILURES sweeps" do
      cred = build_credential(owner: @user, access_token: "old-token",
                              refresh_token: nil, expires_at: 1.minute.ago)

      OauthCredential::MAX_REFRESH_FAILURES.times do
        assert_equal :error, Oauth::TokenService.refresh_credential(cred)
      end

      assert cred.reload.error?, "the sweep must surface a Reconnect state, not wait for a dead connection"
      assert_not_requested :post, TOKEN_ENDPOINT
    end

    test "records the failure and raises ReauthRequired when the provider rejects the refresh" do
      cred = build_credential(owner: @user, access_token: "old-token",
                              refresh_token: "r", expires_at: 1.minute.ago)
      stub_request(:post, TOKEN_ENDPOINT).to_return(status: 400, body: "invalid_grant")

      assert_raises(Oauth::ReauthRequired) do
        Oauth::TokenService.access_token_for(owner: @user, provider: "sentry", user: @user)
      end

      cred.reload
      # A single failure records the error and increments the streak but keeps the
      # credential usable (the sweep retries); it escalates to :error only after
      # MAX_REFRESH_FAILURES consecutive failures.
      assert cred.refresh_error.present?
      assert_equal 1, cred.refresh_failure_count
      assert cred.active?
    end

    test "escalates the credential to error after MAX_REFRESH_FAILURES consecutive rejections" do
      cred = build_credential(owner: @user, access_token: "old-token",
                              refresh_token: "r", expires_at: 1.minute.ago)
      stub_request(:post, TOKEN_ENDPOINT).to_return(status: 400, body: "invalid_grant")

      OauthCredential::MAX_REFRESH_FAILURES.times do
        assert_raises(Oauth::ReauthRequired) do
          Oauth::TokenService.access_token_for(owner: @user, provider: "sentry", user: @user)
        end
      end

      assert cred.reload.error?
    end

    # == fresh: rotation safety ==

    test "does not downgrade to an earlier-expiring token" do
      cred = build_credential(owner: @user, access_token: "old-token",
                              refresh_token: "r", expires_at: 9.minutes.from_now)
      # Response expiry (now + 60s) is earlier than the stored expiry — a downgrade.
      stub_token_endpoint(access_token: "downgrade-token", expires_in: 60)

      assert_raises(Oauth::ReauthRequired) do
        Oauth::TokenService.access_token_for(owner: @user, provider: "sentry", user: @user)
      end

      assert_equal "old-token", cred.reload.access_token
    end

    test "skips the network refresh when a concurrent request already refreshed under the lock" do
      cred = build_credential(owner: @user, access_token: "old-token",
                              refresh_token: "r", expires_at: 1.minute.ago)
      # Simulate a concurrent writer: the row is fresh by the time we hold the lock.
      cred.define_singleton_method(:reload) do |*, **|
        self.access_token = "concurrent-fresh"
        self.expires_at = 2.hours.from_now
        self
      end

      token = Oauth::TokenService.fresh(cred)

      assert_equal "concurrent-fresh", token
      assert_not_requested :post, TOKEN_ENDPOINT
    end

    # == pick_credential: server scoping (scope-driven, oauth-unification §4.4) ==

    test "a per_user oauth server selects the acting user's own credential" do
      server = create(:mcp_server, :custom, scope: @project, auth_type: :oauth, credential_scope: :per_user)
      build_credential(owner: @company, mcp_server: server, access_token: "company-token",
                       expires_at: 1.hour.from_now)
      build_credential(owner: @user, mcp_server: server, access_token: "user-token",
                       expires_at: 1.hour.from_now)

      assert_equal "user-token", Oauth::TokenService.access_token_for(server: server, user: @user)
    end

    test "a shared oauth server selects the scope owner's credential, never the user's" do
      server = create(:mcp_server, :custom, scope: @project, auth_type: :oauth, credential_scope: :shared)
      build_credential(owner: @project, mcp_server: server, access_token: "project-token",
                       expires_at: 1.hour.from_now)
      build_credential(owner: @user, mcp_server: server, access_token: "user-token",
                       expires_at: 1.hour.from_now)

      assert_equal "project-token", Oauth::TokenService.access_token_for(server: server, user: @user)
    end

    test "raises ReauthRequired (connect required) when a per_user oauth server has no credential for the user" do
      server = create(:mcp_server, :custom, scope: @project, auth_type: :oauth, credential_scope: :per_user)
      # A scope-owner credential must NOT satisfy a per_user server — the user connects.
      build_credential(owner: @company, mcp_server: server, access_token: "company-token",
                       expires_at: 1.hour.from_now)

      assert_raises(Oauth::ReauthRequired) do
        Oauth::TokenService.access_token_for(server: server, user: @user)
      end
    end

    test "raises ReauthRequired when a shared oauth server has no scope-owner credential" do
      server = create(:mcp_server, :custom, scope: @project, auth_type: :oauth, credential_scope: :shared)

      assert_raises(Oauth::ReauthRequired) do
        Oauth::TokenService.access_token_for(server: server, user: @user)
      end
    end

    test "never injects another tenant's credential — raises connect-required instead" do
      server = create(:mcp_server, :custom, scope: @project, auth_type: :oauth, credential_scope: :per_user)
      other = create(:user, :admin, company: create(:company))
      build_credential(owner: other, mcp_server: server, access_token: "foreign-token",
                       expires_at: 1.hour.from_now)

      assert_raises(Oauth::ReauthRequired) do
        Oauth::TokenService.access_token_for(server: server, user: @user)
      end
    end

    test "returns nil (no connect signal) for a non-oauth server with no matching credential" do
      server = create(:mcp_server, :custom, scope: @project) # auth_type defaults to :none
      other = create(:user, :admin, company: create(:company))
      build_credential(owner: other, mcp_server: server, access_token: "foreign-token",
                       expires_at: 1.hour.from_now)

      assert_nil Oauth::TokenService.pick_credential(server: server, owner: nil, provider: nil, user: @user)
      assert_nil Oauth::TokenService.access_token_for(server: server, user: @user)
    end

    test "ignores revoked credentials when picking for a server" do
      server = create(:mcp_server, :custom, scope: @project, auth_type: :oauth, credential_scope: :shared)
      build_credential(owner: @project, mcp_server: server, status: :revoked,
                       access_token: "revoked-token", expires_at: 1.hour.from_now)

      # Revoked excluded ⇒ no live credential ⇒ connect required for an oauth server.
      assert_raises(Oauth::ReauthRequired) do
        Oauth::TokenService.pick_credential(server: server, owner: nil, provider: nil, user: @user)
      end
    end

    # == perform_refresh!: resource indicator + time-of-use SSRF guard (§5) ==

    test "sends the RFC 8707 resource indicator on refresh for an MCP-server credential" do
      server = create(:mcp_server, :custom, scope: @project, url: "https://mcp.acme.test/v1",
                      auth_type: :oauth, credential_scope: :shared)
      build_credential(owner: @project, mcp_server: server, access_token: "old",
                       refresh_token: "r", expires_at: 1.minute.from_now)
      stub_token_endpoint(access_token: "new-token", expires_in: 3600)

      Oauth::TokenService.access_token_for(server: server, user: @user)

      assert_requested(:post, TOKEN_ENDPOINT) do |req|
        URI.decode_www_form(req.body).to_h["resource"] == "https://mcp.acme.test/v1"
      end
    end

    test "refuses to refresh against an unsafe (link-local) token_endpoint and signals reauth" do
      evil = OauthClient.new(issuer: "https://evil.test", client_id: "evil-cid", source: "dcr",
                             authorization_endpoint: "https://evil.test/authorize",
                             token_endpoint: "http://169.254.169.254/token")
      evil.save!
      build_credential(owner: @user, oauth_client: evil, access_token: "old",
                       refresh_token: "r", expires_at: 1.minute.ago)

      assert_raises(Oauth::ReauthRequired) do
        Oauth::TokenService.access_token_for(owner: @user, provider: "sentry", user: @user)
      end
      assert_not_requested(:post, "http://169.254.169.254/token")
    end

    # == pick_credential: owner + provider ==

    test "returns the newest active credential for an owner+provider and ignores revoked" do
      older = build_credential(owner: @company, oauth_client: build_client(client_id: "c-old"),
                               access_token: "older", expires_at: 1.hour.from_now)
      newer = build_credential(owner: @company, oauth_client: build_client(client_id: "c-new"),
                               access_token: "newer", expires_at: 1.hour.from_now)
      build_credential(owner: @company, oauth_client: build_client(client_id: "c-revoked"),
                       status: :revoked, access_token: "revoked", expires_at: 1.hour.from_now)
      older.update_column(:updated_at, 2.hours.ago)
      newer.update_column(:updated_at, 1.minute.ago)

      picked = Oauth::TokenService.pick_credential(server: nil, owner: @company, provider: "sentry", user: @user)

      assert_equal newer.id, picked.id
    end

    # == refresh_credential: sweep entry point ==

    test "refresh_credential returns :refreshed and rotates the token when near expiry" do
      cred = build_credential(owner: @user, access_token: "old-token",
                              refresh_token: "old-refresh", expires_at: 1.minute.from_now)
      stub_token_endpoint(access_token: "new-token", refresh_token: "new-refresh", expires_in: 3600)

      assert_equal :refreshed, Oauth::TokenService.refresh_credential(cred)
      assert_equal "new-token", cred.reload.access_token
    end

    test "refresh_credential returns :not_needed when the token is not yet near expiry" do
      cred = build_credential(owner: @user, access_token: "valid-token",
                              refresh_token: "r1", expires_at: 1.hour.from_now)

      assert_equal :not_needed, Oauth::TokenService.refresh_credential(cred)
      assert_not_requested :post, TOKEN_ENDPOINT
    end

    test "refresh_credential returns :error and marks the credential when the refresh fails" do
      cred = build_credential(owner: @user, access_token: "old-token",
                              refresh_token: "old-refresh", expires_at: 1.minute.from_now)
      stub_request(:post, TOKEN_ENDPOINT).to_return(status: 400, body: "nope")

      assert_equal :error, Oauth::TokenService.refresh_credential(cred)
      assert_equal 1, cred.reload.refresh_failure_count
    end

    private

    def build_client(client_id: "public-client", client_secret: nil)
      client = OauthClient.new(
        issuer: "https://provider.test",
        authorization_endpoint: "https://provider.test/oauth/authorize",
        token_endpoint: TOKEN_ENDPOINT,
        client_id: client_id,
        source: "static"
      )
      client.client_secret = client_secret if client_secret
      client.save!
      client
    end

    def build_credential(owner:, oauth_client: @client, provider: "sentry", mcp_server: nil,
                         status: :active, access_token: nil, refresh_token: nil, expires_at: nil)
      cred = OauthCredential.new(owner: owner, oauth_client: oauth_client, provider: provider,
                                 mcp_server: mcp_server, status: status)
      cred.access_token = access_token if access_token
      cred.refresh_token = refresh_token if refresh_token
      cred.expires_at = expires_at
      cred.save!
      cred
    end

    def stub_token_endpoint(access_token:, expires_in:, refresh_token: nil)
      body = { access_token: access_token, token_type: "Bearer", expires_in: expires_in }
      body[:refresh_token] = refresh_token if refresh_token
      stub_request(:post, TOKEN_ENDPOINT)
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: body.to_json)
    end
  end
end
