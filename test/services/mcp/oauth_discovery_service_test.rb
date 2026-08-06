# frozen_string_literal: true

require "test_helper"

module MCP
  # Exercises MCP::OauthDiscoveryService against the real OauthClient model
  # (testing doctrine R2: don't mock what you own). Only the network boundary is
  # faked, via WebMock (R4: contract-test the HTTP boundary).
  #
  # SECURITY FOCUS: the discovery flow (RFC 9728 → 8414 → 7591) fetches urls that
  # are entirely attacker-controlled. These tests assert the SSRF guard fires at
  # EVERY step (private/loopback/link-local, http downgrade, redirect-to-internal,
  # redirect caps) and that malicious metadata is rejected.
  class OauthDiscoveryServiceTest < ActiveSupport::TestCase
    MCP_URL   = "https://mcp.example.com/v1"
    PRM_URL   = "https://mcp.example.com/.well-known/oauth-protected-resource"
    # RFC 9728 §3.1: the well-known segment goes BEFORE the resource path.
    PATH_PRM_URL = "https://mcp.example.com/.well-known/oauth-protected-resource/v1"
    ISSUER    = "https://auth.example.com"
    ASM_URL   = "https://auth.example.com/.well-known/oauth-authorization-server"
    OIDC_URL  = "https://auth.example.com/.well-known/openid-configuration"
    AUTH_EP   = "https://auth.example.com/authorize"
    TOKEN_EP  = "https://auth.example.com/token"
    REG_EP    = "https://auth.example.com/register"

    setup do
      Rails.logger.stubs(:warn)
      # Deterministic, network-free resolution: the validator resolves hostnames
      # with libc getaddrinfo (the same resolver Net::HTTP dials with), so stub
      # THAT to treat every hostname as public. Literal-IP hosts (10.0.0.1,
      # 127.0.0.1, 169.254.169.254) are classified by IPAddr and never hit this
      # path, so they stay blocked.
      Addrinfo.stubs(:getaddrinfo).returns([])
      # Do not pin (which would use real public DNS); the per-hop guard is the tested backstop.
      UrlSafetyValidator.stubs(:resolve_public_ipv4).returns(nil)
    end

    # ============================ HAPPY PATH ============================

    test "runs a→c and returns a persisted dcr client, resource indicator, and scopes" do
      stub_probe
      stub_prm
      stub_asm
      stub_registration(body: { client_id: "dcr-client-id" })

      result = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      client = result.oauth_client
      assert_equal "dcr", client.source
      assert_equal ISSUER, client.issuer
      assert_equal "dcr-client-id", client.client_id
      assert_equal AUTH_EP, client.authorization_endpoint
      assert_equal TOKEN_EP, client.token_endpoint
      assert_equal REG_EP, client.registration_endpoint
      assert client.persisted?
      assert_not client.confidential?, "PKCE-only registration must not be confidential"

      # RFC 8707 resource indicator = canonical MCP url.
      assert_equal MCP_URL, result.resource
      # Scopes preferred from PRM scopes_supported.
      assert_equal "read write", result.scopes
    end

    # ============================ CIMD ============================

    test "uses CIMD (no DCR POST) when the AS advertises client_id_metadata_document support" do
      stub_probe
      stub_prm
      stub_asm(body: default_asm_body.merge("client_id_metadata_document_supported" => true))
      # Deliberately NO stub_registration: any DCR POST would be an unstubbed request.

      result = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      client = result.oauth_client

      expected_client_id = "#{Settings.protocol}://#{Settings.domain}/oauth/client-metadata.json"
      assert_equal "cimd", client.source
      assert_equal expected_client_id, client.client_id
      assert_equal ISSUER, client.issuer
      assert_equal AUTH_EP, client.authorization_endpoint
      assert_equal TOKEN_EP, client.token_endpoint
      assert_not client.confidential?, "CIMD clients are public (PKCE-only)"
      assert client.persisted?
      assert_not_requested :post, REG_EP
    end

    test "reuses a persisted CIMD client on a subsequent connect instead of re-creating it" do
      stub_probe
      stub_prm
      stub_asm(body: default_asm_body.merge("client_id_metadata_document_supported" => true))

      first = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL).oauth_client
      second = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL).oauth_client

      assert_equal first.id, second.id
      assert_equal 1, OauthClient.where(source: "cimd", issuer: ISSUER).count
    end

    test "prefers DCR when the AS does not advertise CIMD support" do
      stub_probe
      stub_prm
      stub_asm # default ASM has no client_id_metadata_document_supported flag
      stub_registration(body: { client_id: "dcr-client-id" })

      assert_equal "dcr", MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL).oauth_client.source
    end

    test "registers with the DCR endpoint as the product, \"Aixle Flow\"" do
      stub_probe
      stub_prm
      stub_asm
      stub_registration(body: { client_id: "dcr-client-id" })

      MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      assert_requested :post, REG_EP do |req|
        JSON.parse(req.body)["client_name"] == "Aixle Flow"
      end
    end

    test "falls back to the well-known PRM path when WWW-Authenticate has no hint" do
      stub_request(:get, MCP_URL).to_return(status: 401, body: "")
      stub_request(:get, PATH_PRM_URL).to_return(status: 404)
      stub_prm
      stub_asm
      stub_registration(body: { client_id: "dcr-client-id" })

      result = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      assert_equal "dcr-client-id", result.oauth_client.client_id
      assert_requested :get, PRM_URL
    end

    test "discovers a path-carrying issuer by inserting the well-known segment (RFC 8414 3.1)" do
      # Airtable's issuer is https://airtable.com/oauth2/v1. RFC 8414 puts the
      # well-known segment BEFORE the path; only appending it 404s, and the 404
      # body is a ~300 KB HTML page, so the request used to die on MAX_BYTES.
      path_issuer = "https://auth.example.com/oauth2/v1"
      inserted    = "https://auth.example.com/.well-known/oauth-authorization-server/oauth2/v1"
      appended    = "https://auth.example.com/oauth2/v1/.well-known/oauth-authorization-server"

      stub_probe
      stub_prm(body: default_prm_body.merge(authorization_servers: [ path_issuer ]))
      stub_request(:get, inserted).to_return(
        status: 200, headers: json_headers,
        body: default_asm_body.merge("issuer" => path_issuer).to_json
      )
      stub_registration(body: { client_id: "dcr-client-id" })

      result = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      assert_equal path_issuer, result.oauth_client.issuer
      assert_requested :get, inserted
      assert_not_requested :get, appended
    end

    test "discovers via openid-configuration when oauth-authorization-server 404s" do
      stub_probe
      stub_prm
      stub_request(:get, ASM_URL).to_return(status: 404, body: "")
      stub_request(:get, OIDC_URL).to_return(
        status: 200, headers: json_headers, body: default_asm_body.to_json
      )
      stub_registration(body: { client_id: "dcr-client-id" })

      result = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      assert_equal "dcr-client-id", result.oauth_client.client_id
      assert_requested :get, OIDC_URL
    end

    test "persists an encrypted secret and stays confidential when the AS issues one" do
      stub_probe
      stub_prm
      stub_asm
      stub_registration(body: { client_id: "dcr-client-id", client_secret: "top-secret" })

      client = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL).oauth_client

      assert client.confidential?
      assert_equal "top-secret", client.client_secret
      assert client.encrypted_client_secret.present?
    end

    test "scrubs bearer-capable fields from the stored metadata" do
      stub_probe
      stub_prm
      stub_asm
      stub_registration(body: {
        client_id: "dcr-client-id",
        client_secret: "top-secret",
        registration_access_token: "reg-token"
      })

      client = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL).oauth_client

      dcr = client.metadata["dcr"]
      assert_equal "dcr-client-id", dcr["client_id"]
      assert_not dcr.key?("client_secret"), "client_secret must be scrubbed from plaintext metadata"
      assert_not dcr.key?("registration_access_token"), "registration_access_token must be scrubbed"
      assert client.metadata.key?("prm")
      assert client.metadata.key?("asm")
    end

    test "caches PRM/ASM metadata in Rails.cache keyed by issuer hash" do
      # The test env uses a null cache store; swap in a real in-memory store so
      # the write is observable (mocha auto-unstubs after the test).
      memory = ActiveSupport::Cache::MemoryStore.new
      Rails.stubs(:cache).returns(memory)
      stub_probe
      stub_prm
      stub_asm
      stub_registration(body: { client_id: "dcr-client-id" })

      MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      key = "mcp_oauth_meta:#{Digest::SHA256.hexdigest(ISSUER)}"
      cached = memory.read(key)
      assert_not_nil cached
      assert cached.key?("prm")
      assert cached.key?("asm")
    end

    test "reuses an existing dcr client for the issuer instead of re-registering" do
      existing = OauthClient.create!(
        source: "dcr", issuer: ISSUER, client_id: "already-registered",
        authorization_endpoint: "https://auth.example.com/old-authorize",
        token_endpoint: "https://auth.example.com/old-token"
      )
      stub_probe
      stub_prm
      stub_asm
      # Deliberately NO registration stub — reuse must not POST to register.

      result = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      assert_equal existing.id, result.oauth_client.id
      assert_not_requested :post, REG_EP
      # Endpoints refreshed from the freshly-discovered + guarded ASM.
      assert_equal AUTH_EP, result.oauth_client.reload.authorization_endpoint
      assert_equal TOKEN_EP, result.oauth_client.token_endpoint
    end

    test "reuses a dcr client when the stored redirect_uri still matches the deployment callback" do
      current = "#{Settings.protocol}://#{Settings.domain}/oauth/callback"
      existing = OauthClient.create!(
        source: "dcr", issuer: ISSUER, client_id: "still-valid",
        authorization_endpoint: "https://auth.example.com/old-authorize",
        token_endpoint: "https://auth.example.com/old-token",
        metadata: { "redirect_uri" => current }
      )
      stub_probe
      stub_prm
      stub_asm
      # No registration stub — a matching redirect must not re-register.

      result = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      assert_equal existing.id, result.oauth_client.id
      assert_not_requested :post, REG_EP
    end

    test "re-registers a dcr client when the stored redirect_uri no longer matches the deployment callback" do
      # Simulates a rotated dev tunnel: the client was registered under an old host,
      # so its pinned redirect_uri would make every authorize fail. Discovery must
      # drop it and register fresh rather than reuse the poisoned client.
      stale = OauthClient.create!(
        source: "dcr", issuer: ISSUER, client_id: "stale-client",
        authorization_endpoint: "https://auth.example.com/old-authorize",
        token_endpoint: "https://auth.example.com/old-token",
        metadata: { "redirect_uri" => "https://old-tunnel.example.dev/oauth/callback" }
      )
      stub_probe
      stub_prm
      stub_asm
      stub_registration(body: { client_id: "fresh-client" })

      result = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      assert_requested :post, REG_EP
      assert_equal "fresh-client", result.oauth_client.client_id
      assert_not OauthClient.exists?(stale.id), "stale client should be dropped"
      assert_equal 1, OauthClient.where(source: "dcr", issuer: ISSUER).count
    end

    test "prefers ASM scopes when PRM omits scopes_supported" do
      stub_probe
      stub_prm(body: { authorization_servers: [ ISSUER ] }) # no scopes_supported
      stub_asm(body: default_asm_body.merge("scopes_supported" => %w[repo user]))
      stub_registration(body: { client_id: "dcr-client-id" })

      result = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      assert_equal "repo user", result.scopes
    end

    # ==================== SSRF REJECTION (per step) ====================

    test "rejects a private-IP MCP url before any request" do
      error = assert_raises(MCP::UnsafeUrlError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: "https://10.0.0.1/v1")
      end
      assert_match(/unsafe url/, error.message)
      assert_not_requested :get, %r{10\.0\.0\.1}
    end

    test "rejects a private-IP authorization_servers entry from PRM" do
      stub_probe
      stub_prm(body: { authorization_servers: [ "http://10.0.0.1" ] })

      assert_raises(MCP::UnsafeUrlError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    test "rejects a link-local token_endpoint from the authorization-server metadata" do
      stub_probe
      stub_prm
      stub_asm(body: default_asm_body.merge("token_endpoint" => "http://169.254.169.254/token"))

      assert_raises(MCP::UnsafeUrlError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
      assert_not_requested :get, %r{169\.254\.169\.254}
    end

    # ======================== PROBE SHAPE + PRM FALLBACK ========================
    # A bare GET is not an MCP request. Surveyed against the catalog, 23 of 178 hosts
    # answer one with 405 and 13 with 406, and the challenge we need rides on the
    # response we thereby never get.

    test "the probe announces the streamable-HTTP transport" do
      stub_probe
      stub_prm
      stub_asm
      stub_registration

      MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      assert_requested :get, MCP_URL, headers: { "Accept" => "application/json, text/event-stream" }
    end

    test "a server that refuses a bare GET is asked again with an MCP initialize" do
      stub_request(:get, MCP_URL).to_return(status: 405)
      stub_request(:post, MCP_URL).to_return(status: 401,
                                             headers: { "WWW-Authenticate" => default_www_authenticate })
      stub_prm
      stub_asm
      stub_registration

      client = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL).oauth_client

      assert_requested :post, MCP_URL, body: hash_including("method" => "initialize")
      assert_equal "dcr-client-id", client.client_id
    end

    test "a server that answers the bare GET is not asked twice" do
      stub_probe
      stub_prm
      stub_asm
      stub_registration

      MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      assert_not_requested :post, MCP_URL
    end

    test "falls back to the path-aware metadata url before the origin-level one" do
      stub_probe(www_authenticate: 'Bearer realm="OAuth"') # no resource_metadata hint
      stub_request(:get, PATH_PRM_URL).to_return(status: 200, headers: json_headers,
                                                 body: default_prm_body.to_json)
      stub_asm
      stub_registration

      MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      assert_requested :get, PATH_PRM_URL
      assert_not_requested :get, PRM_URL
    end

    test "falls back to the origin-level metadata url when the path-aware one is absent" do
      stub_probe(www_authenticate: 'Bearer realm="OAuth"')
      stub_request(:get, PATH_PRM_URL).to_return(status: 404)
      stub_prm
      stub_asm
      stub_registration

      MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      assert_requested :get, PRM_URL
    end

    test "says the server advertises no authorization server when no candidate answers" do
      stub_probe(www_authenticate: 'Bearer realm="OAuth"')
      stub_request(:get, PATH_PRM_URL).to_return(status: 404)
      stub_request(:get, PRM_URL).to_return(status: 404)

      error = assert_raises(MCP::NoAuthServerError) { MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL) }

      assert_match(/did not advertise/, error.user_message)
    end

    # ======================== MANUAL CLIENT ========================
    # The way out for an authorization server that will not register us: an operator
    # registers the OAuth app themselves and pastes its credentials.

    test "a manual client is used instead of registering, and gets its endpoints from discovery" do
      server = create(:mcp_server, :custom, auth_type: :oauth, url: MCP_URL)
      manual = OauthClient.create!(source: OauthClient::SOURCE_MANUAL, client_id: "operator-cid",
                                   mcp_server: server, client_secret: "operator-secret")
      stub_probe
      stub_prm
      stub_asm
      # Deliberately NO stub_registration: registering is what this server refuses.

      result = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL, manual_client: manual)

      client = result.oauth_client
      assert_equal manual.id, client.id
      assert_equal "operator-cid", client.client_id
      assert_equal ISSUER, client.issuer
      assert_equal AUTH_EP, client.authorization_endpoint
      assert_equal TOKEN_EP, client.token_endpoint
      assert client.confidential?, "an operator-supplied secret must survive discovery"
      assert_not_requested :post, REG_EP
    end

    test "a manual client is preferred over an already-registered dcr client for the same issuer" do
      server = create(:mcp_server, :custom, auth_type: :oauth, url: MCP_URL)
      manual = OauthClient.create!(source: OauthClient::SOURCE_MANUAL, client_id: "operator-cid",
                                   mcp_server: server)
      OauthClient.create!(source: "dcr", issuer: ISSUER, client_id: "old-dcr-cid",
                          authorization_endpoint: AUTH_EP, token_endpoint: TOKEN_EP)
      stub_probe
      stub_prm
      stub_asm

      client = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL, manual_client: manual).oauth_client

      assert_equal "operator-cid", client.client_id
    end

    test "a manual client with no scopes of its own takes the ones discovery advertises" do
      server = create(:mcp_server, :custom, auth_type: :oauth, url: MCP_URL)
      manual = OauthClient.create!(source: OauthClient::SOURCE_MANUAL, client_id: "operator-cid",
                                   mcp_server: server)
      stub_probe
      stub_prm
      stub_asm

      MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL, manual_client: manual)

      assert_equal "read write", manual.reload.scopes
    end

    # ==================== REGISTRATION FAILURE DIAGNOSIS ====================
    # "Couldn't connect" is a lie when the server answered perfectly well and simply
    # refused to register us. These assert the WHY survives, and only via the allowlist.

    test "a registration refused for an unapproved callback says an operator must configure a client" do
      stub_probe
      stub_prm
      stub_asm
      # Vercel's real answer: its authorization server approves loopback callbacks
      # only, so no hosted deployment can ever register itself.
      stub_registration(status: 400, body: { error: "invalid_redirect_uri",
                                             error_description: "The provided redirect URIs are not approved." })

      error = assert_raises(MCP::RegistrationError) { MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL) }

      assert_equal "invalid_redirect_uri", error.code
      assert_match(/callback URL/, error.user_message)
      assert_match(/operator/, error.user_message)
    end

    test "an authorization server with no registration endpoint says so" do
      stub_probe
      stub_prm
      stub_asm(body: default_asm_body.except("registration_endpoint"))

      error = assert_raises(MCP::RegistrationError) { MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL) }

      assert_equal MCP::RegistrationError::NO_ENDPOINT, error.code
      assert_match(/does not support automatic app registration/, error.user_message)
    end

    test "an unrecognised error code, and its prose, never reach the user" do
      stub_probe
      stub_prm
      stub_asm
      stub_registration(status: 400, body: { error: "im_a_teapot",
                                             error_description: "<script>alert(1)</script>" })

      error = assert_raises(MCP::RegistrationError) { MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL) }

      assert_nil error.code
      assert_equal MCP::DiscoveryError::GENERIC, error.user_message
      assert_no_match(/script/, error.user_message)
      assert_no_match(/script/, error.message)
    end

    test "a registration failure that is not JSON falls back to the generic message" do
      stub_probe
      stub_prm
      stub_asm
      stub_request(:post, REG_EP).to_return(status: 502, body: "<html>bad gateway</html>")

      error = assert_raises(MCP::RegistrationError) { MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL) }

      assert_nil error.code
      assert_equal MCP::DiscoveryError::GENERIC, error.user_message
    end

    test "a transport failure stays generic — it really is a connection problem" do
      stub_probe
      stub_prm
      stub_asm
      stub_request(:post, REG_EP).to_timeout

      error = assert_raises(MCP::RegistrationError) { MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL) }

      assert_nil error.code
      assert_equal MCP::DiscoveryError::GENERIC, error.user_message
    end

    test "rejects a loopback registration_endpoint" do
      stub_probe
      stub_prm
      stub_asm(body: default_asm_body.merge("registration_endpoint" => "https://127.0.0.1/register"))

      assert_raises(MCP::UnsafeUrlError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
      assert_not_requested :post, %r{127\.0\.0\.1}
    end

    test "rejects a private-IP authorization_endpoint" do
      stub_probe
      stub_prm
      stub_asm(body: default_asm_body.merge("authorization_endpoint" => "https://192.168.1.5/authorize"))

      assert_raises(MCP::UnsafeUrlError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    # ==================== SSRF REJECTION (http downgrade at each hop) ==========

    test "rejects an http MCP url (https required)" do
      assert_raises(MCP::UnsafeUrlError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: "http://mcp.example.com/v1")
      end
    end

    test "rejects an http PRM url advertised via WWW-Authenticate" do
      stub_request(:get, MCP_URL).to_return(
        status: 401,
        headers: { "WWW-Authenticate" => 'Bearer resource_metadata="http://mcp.example.com/.well-known/oauth-protected-resource"' }
      )

      assert_raises(MCP::UnsafeUrlError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    test "rejects an http issuer in authorization_servers" do
      stub_probe
      stub_prm(body: { authorization_servers: [ "http://auth.example.com" ] })

      assert_raises(MCP::UnsafeUrlError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    test "rejects an http token_endpoint on an otherwise-public host" do
      stub_probe
      stub_prm
      stub_asm(body: default_asm_body.merge("token_endpoint" => "http://auth.example.com/token"))

      assert_raises(MCP::UnsafeUrlError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    # ==================== MALICIOUS METADATA ====================

    test "rejects a redirect from a public host to a private IP" do
      stub_probe
      stub_request(:get, PRM_URL).to_return(status: 302, headers: { "Location" => "http://10.0.0.1/pwn" })

      assert_raises(MCP::UnsafeUrlError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
      assert_not_requested :get, %r{10\.0\.0\.1}
    end

    test "aborts a redirect chain that exceeds the hop cap" do
      stub_probe
      stub_request(:get, PRM_URL).to_return(status: 302, headers: { "Location" => "https://a.example.com/1" })
      stub_request(:get, PATH_PRM_URL).to_return(status: 404)
      stub_request(:get, "https://a.example.com/1").to_return(status: 302, headers: { "Location" => "https://b.example.com/2" })
      stub_request(:get, "https://b.example.com/2").to_return(status: 302, headers: { "Location" => "https://c.example.com/3" })
      stub_request(:get, "https://c.example.com/3").to_return(status: 302, headers: { "Location" => "https://d.example.com/4" })

      assert_raises(MCP::DiscoveryError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
      assert_not_requested :get, "https://d.example.com/4"
    end

    test "rejects a metadata response larger than the body cap" do
      stub_probe
      stub_request(:get, PRM_URL).to_return(
        status: 200, headers: json_headers, body: "x" * (300 * 1024)
      )
      stub_request(:get, PATH_PRM_URL).to_return(status: 404)

      assert_raises(MCP::DiscoveryError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    test "rejects a non-JSON PRM body" do
      stub_probe
      stub_request(:get, PRM_URL).to_return(status: 200, body: "<html>not json</html>")
      stub_request(:get, PATH_PRM_URL).to_return(status: 404)

      assert_raises(MCP::DiscoveryError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    test "raises NoAuthServerError when authorization_servers is empty" do
      stub_probe
      stub_prm(body: { authorization_servers: [] })

      assert_raises(MCP::NoAuthServerError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    test "raises NoAuthServerError when no authorization-server metadata is discoverable" do
      stub_probe
      stub_prm
      stub_request(:get, ASM_URL).to_return(status: 404, body: "")
      stub_request(:get, OIDC_URL).to_return(status: 404, body: "")

      assert_raises(MCP::NoAuthServerError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    test "raises RegistrationError when the AS advertises no registration endpoint" do
      stub_probe
      stub_prm
      stub_asm(body: default_asm_body.except("registration_endpoint"))

      assert_raises(MCP::RegistrationError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    test "raises RegistrationError on a non-2xx registration response" do
      stub_probe
      stub_prm
      stub_asm
      stub_request(:post, REG_EP).to_return(status: 400, body: "bad_request")

      assert_raises(MCP::RegistrationError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    test "raises RegistrationError when the DCR response has no client_id" do
      stub_probe
      stub_prm
      stub_asm
      stub_registration(body: { token_endpoint_auth_method: "none" })

      assert_raises(MCP::RegistrationError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    test "raises RegistrationError on an unparseable DCR response" do
      stub_probe
      stub_prm
      stub_asm
      stub_request(:post, REG_EP).to_return(status: 200, body: "not json")

      assert_raises(MCP::RegistrationError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    test "rejects a DCR response that echoes a private-IP client_uri" do
      stub_probe
      stub_prm
      stub_asm
      stub_registration(body: { client_id: "dcr-client-id", client_uri: "https://10.0.0.1/app" })

      assert_raises(MCP::UnsafeUrlError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    test "rejects a DCR response that echoes a private-IP redirect_uri" do
      stub_probe
      stub_prm
      stub_asm
      stub_registration(body: { client_id: "dcr-client-id", redirect_uris: [ "https://169.254.169.254/cb" ] })

      assert_raises(MCP::UnsafeUrlError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    test "accepts a DCR response that echoes back our own redirect_uri" do
      # A conforming AS echoes the redirect_uri we sent. That value is ours, so
      # guarding it only ever rejects our own deployment — which is exactly what
      # happened to Supabase in dev, where the callback host is localhost.
      ours = "#{Settings.protocol}://#{Settings.domain}/oauth/callback"
      stub_probe
      stub_prm
      stub_asm
      stub_registration(body: { client_id: "dcr-client-id", redirect_uris: [ ours ] })

      result = MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)

      assert_equal "dcr-client-id", result.oauth_client.client_id
    end

    test "still rejects an extra internal redirect_uri alongside our own" do
      ours = "#{Settings.protocol}://#{Settings.domain}/oauth/callback"
      stub_probe
      stub_prm
      stub_asm
      stub_registration(body: { client_id: "dcr-client-id", redirect_uris: [ ours, "http://169.254.169.254/cb" ] })

      assert_raises(MCP::UnsafeUrlError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    test "reuse re-guards a persisted endpoint that has since become unsafe" do
      OauthClient.create!(
        source: "dcr", issuer: ISSUER, client_id: "already-registered",
        authorization_endpoint: "https://10.0.0.1/authorize",
        token_endpoint: "https://10.0.0.1/token"
      )
      stub_probe
      stub_prm
      # ASM still resolves to public endpoints, but reuse re-guards the STORED
      # (attacker-authored) endpoints first — time-of-use validation.
      stub_asm

      assert_raises(MCP::UnsafeUrlError) do
        MCP::OauthDiscoveryService.prepare(mcp_url: MCP_URL)
      end
    end

    private

    def json_headers
      { "Content-Type" => "application/json" }
    end

    def default_www_authenticate
      %(Bearer resource_metadata="#{PRM_URL}")
    end

    def default_prm_body
      { authorization_servers: [ ISSUER ], scopes_supported: %w[read write], resource: MCP_URL }
    end

    def default_asm_body
      {
        "issuer" => ISSUER,
        "authorization_endpoint" => AUTH_EP,
        "token_endpoint" => TOKEN_EP,
        "registration_endpoint" => REG_EP,
        "scopes_supported" => %w[read write]
      }
    end

    def stub_probe(www_authenticate: default_www_authenticate)
      stub_request(:get, MCP_URL).to_return(
        status: 401, headers: { "WWW-Authenticate" => www_authenticate }
      )
    end

    def stub_prm(body: default_prm_body)
      stub_request(:get, PRM_URL).to_return(status: 200, headers: json_headers, body: body.to_json)
    end

    def stub_asm(body: default_asm_body)
      stub_request(:get, ASM_URL).to_return(status: 200, headers: json_headers, body: body.to_json)
    end

    def stub_registration(status: 201, body: { client_id: "dcr-client-id" })
      stub_request(:post, REG_EP).to_return(status: status, headers: json_headers, body: body.to_json)
    end
  end
end
