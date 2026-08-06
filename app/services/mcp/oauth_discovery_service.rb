# frozen_string_literal: true

module MCP
  # Discovers an MCP server's OAuth 2.1 configuration and prepares a persisted
  # client for the authorize flow, per the MCP authorization spec:
  #
  #   (a) probe the MCP url                → RFC 9728 protected-resource metadata
  #   (b) fetch authorization-server meta  → RFC 8414 / OIDC discovery endpoints
  #   (c) dynamic client registration      → RFC 7591 (persisted source:"dcr" client)
  #
  # This is the Rails-owned analogue of 1MCP's SDKOAuthClientProvider
  # (oauth-unification.md §5) but with PER-TENANT identity — which 1MCP lacks
  # (it keys tokens by server name only). The persisted client is reused across
  # connects; per-user/per-scope credentials are handled downstream by
  # Oauth::TokenService / OauthCredential.
  #
  # ============================ SSRF DOCTRINE ============================
  # Phase 1's OAuth endpoints came only from the trusted Oauth::Providers
  # registry (zero SSRF surface). Discovery BREAKS that invariant: EVERY url
  # here is attacker-influenced — a user-pasted MCP url, a WWW-Authenticate
  # header, RFC 9728 / 8414 JSON, and the DCR response. Treat all of it as
  # hostile. The rules, enforced by #guard! and #safe_fetch:
  #
  #   1. Validate before EVERY fetch. UrlSafetyValidator.errors_for(url,
  #      require_https: true) — no exceptions — for the MCP url, the PRM url,
  #      EVERY authorization_servers entry, the ASM metadata url, the
  #      authorization/token/registration endpoints, and any DCR-echoed
  #      redirect_uris/client_uri. require_https rejects http, blocked hosts,
  #      literal private/loopback/link-local IPs, and hostnames that DNS-resolve
  #      into private space.
  #   2. Re-validate on EVERY redirect hop. Redirects are followed manually
  #      (Net::HTTP does not auto-follow); each Location is guarded before the
  #      next request. Capped at MAX_REDIRECTS hops.
  #   3. Validate at time-of-USE. A persisted dcr endpoint is still
  #      attacker-authored: a reused client re-guards its endpoints, and
  #      Oauth::TokenService re-guards token_endpoint before every refresh
  #      (that check lives in WIRING, not here).
  #   4. Response limits: TIMEOUT connect/read timeout; MAX_BYTES body cap read
  #      capped (Content-Length is not trusted); non-2xx rejected except the
  #      deliberate probe in step (a) and the DCR POST in step (c), whose failure
  #      body is read for an allowlisted RFC 7591 error code and nothing else.
  #   5. No secrets/metadata in logs. Discovered metadata may embed tokens/urls;
  #      exceptions carry only a host + status, never a body or a full url.
  #   6. DNS pinning caveat (TOCTOU): errors_for resolves, then the HTTP client
  #      resolves AGAIN. Where feasible the validated public IPv4 is pinned into
  #      the request (UrlSafetyValidator.resolve_public_ipv4); the redirect cap +
  #      per-hop re-validation are the always-present backstop when pinning is
  #      unavailable.
  # =======================================================================
  class OauthDiscoveryService
    Result = Struct.new(:oauth_client, :resource, :scopes, keyword_init: true)

    # Internal transport failure (non-2xx, oversize, network, too many redirects).
    # A DiscoveryError so callers can rescue the whole family; distinct from
    # UnsafeUrlError so an SSRF rejection is never silently downgraded.
    FetchError = Class.new(DiscoveryError)

    Response = Struct.new(:status, :net_response, :body) do
      def header(name) = net_response[name]
      def success? = status.between?(200, 299)
    end

    SOURCE_DCR = "dcr"
    SOURCE_CIMD = "cimd"
    CLIENT_NAME = "Aixle Flow"
    TIMEOUT = 5
    MAX_REDIRECTS = 3
    MAX_BYTES = 256 * 1024
    REDIRECT_CODES = [ 301, 302, 303, 307, 308 ].freeze
    METHOD_PRESERVING_REDIRECTS = [ 307, 308 ].freeze
    # Keys in a DCR response that are bearer-capable / secret and must NEVER land
    # in the plaintext metadata jsonb (client_secret is stored encrypted instead).
    SENSITIVE_DCR_KEYS = %w[client_secret registration_access_token].freeze
    METADATA_CACHE_TTL = 1.hour
    # What an MCP client sends: the transport is streamable HTTP, which may answer
    # either as JSON or as an SSE stream, and servers reject a request that does not
    # say it accepts both.
    MCP_ACCEPT = "application/json, text/event-stream"
    # Metadata documents (RFC 9728 / 8414) are plain JSON, and asking for a stream
    # there would be noise.
    DEFAULT_ACCEPT = "application/json"
    # Statuses that mean "not like that" rather than "no": worth one retry with a
    # real MCP request before giving up on getting a challenge out of the server.
    PROBE_RETRY_STATUSES = [ 400, 404, 405, 406 ].freeze
    # The MCP handshake, used purely as a probe: it is the one request every server
    # answers, it needs no authentication, and it changes nothing server-side. The
    # version is the floor we speak, not a requirement — a server that only supports
    # a newer revision still answers, which is all a probe needs.
    INITIALIZE_REQUEST = {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: CLIENT_NAME, version: "1" }
      }
    }.freeze

    # Entry point WIRING calls from the connect action. Runs steps a→c and returns
    # a persisted source:"dcr" OauthClient + the RFC 8707 resource indicator
    # (canonical MCP url) + discovered default scopes. Raises MCP::DiscoveryError
    # (or a subclass) on ANY failure including every SSRF rejection. NEVER returns
    # a partially-validated client.
    def self.prepare(mcp_url:)
      new(mcp_url).prepare
    end

    def initialize(mcp_url)
      @mcp_url = mcp_url.to_s
    end

    def prepare
      prm = probe_protected_resource
      issuer = prm[:authorization_servers].first
      asm = fetch_authorization_server_metadata(issuer)
      client = register_client(asm, prm)

      Result.new(
        oauth_client: client,
        resource: canonical_resource,
        scopes: prm[:scopes].presence || asm[:scopes].presence
      )
    end

    private

    # ---- Step (a): probe MCP url → RFC 9728 protected-resource metadata --------
    def probe_protected_resource
      guard!(@mcp_url)
      probe = probe_challenge

      prm = first_usable_prm(prm_candidates(probe))
      raise NoAuthServerError, "no protected-resource metadata" if prm.nil?

      servers = Array(prm["authorization_servers"]).map { |s| s.to_s.strip }.reject(&:blank?)
      raise NoAuthServerError, "protected-resource metadata lists no authorization_servers" if servers.empty?

      servers.each { |server| guard!(server) }

      { authorization_servers: servers, scopes: scope_string(prm["scopes_supported"]), raw: prm }
    end

    # The response we hope carries a WWW-Authenticate challenge. Unauthenticated, and
    # any status is fine — the header is the whole point, not the body.
    #
    # SHAPE MATTERS. A bare GET is not an MCP request, and a lot of servers say so:
    # in a survey of 178 catalog hosts, 23 answered it with 405 and 13 with 406, and
    # Grafana 302s it while answering the SAME url with a 401 + resource_metadata
    # once the streamable-HTTP Accept header is present. So the probe asks the way a
    # client would, and when the server refuses the shape outright it is asked again
    # with the one request every MCP server must answer.
    def probe_challenge
      probe = safe_fetch(@mcp_url, allow_statuses: :any, accept: MCP_ACCEPT)
      return probe if resource_metadata_url(probe).present?
      return probe if PROBE_RETRY_STATUSES.exclude?(probe.status)

      retried = safe_fetch(@mcp_url, method: :post, json: INITIALIZE_REQUEST,
                           allow_statuses: :any, accept: MCP_ACCEPT)
      resource_metadata_url(retried).present? ? retried : probe
    rescue FetchError
      # The retry is best-effort: if it cannot complete, the first probe's answer (or
      # the well-known fallbacks) still stands.
      probe || raise
    end

    # In order: what the server told us, then the two well-known locations.
    def prm_candidates(probe)
      [ resource_metadata_url(probe), path_aware_prm_url, origin_prm_url ].compact_blank.uniq
    end

    # First candidate that answers with usable metadata wins. A 404, a non-2xx or a
    # body that is not a JSON object moves on to the next; an UnsafeUrlError does NOT
    # — a hint pointing somewhere we must not go is a security signal, not a miss.
    def first_usable_prm(candidates)
      candidates.each do |url|
        guard!(url)

        begin
          body = JSON.parse(safe_fetch(url).body)
        rescue FetchError, JSON::ParserError
          next
        end

        return body if body.is_a?(Hash)
      end

      nil
    end

    # Parse `resource_metadata="https://..."` (quoted or bare) out of a
    # WWW-Authenticate challenge, if present.
    def resource_metadata_url(response)
      header = response.header("www-authenticate")
      return nil if header.blank?

      match = header.match(/resource_metadata\s*=\s*"?([^",\s]+)"?/i)
      match && match[1]
    end

    # RFC 9728 §3.1 inserts the well-known segment BEFORE the resource path, so a
    # server at /mcp publishes its metadata at
    # `/.well-known/oauth-protected-resource/mcp`. Only the origin-level form used to
    # be tried, which is why a server like Grafana — which publishes exclusively at
    # the path-aware url and 404s the other — could never be discovered from the
    # fallback. nil for a url with no path of its own.
    def path_aware_prm_url
      path = URI.parse(@mcp_url).path.to_s.chomp("/")
      return nil if path.blank?

      "#{origin(@mcp_url)}/.well-known/oauth-protected-resource#{path}"
    end

    def origin_prm_url
      "#{origin(@mcp_url)}/.well-known/oauth-protected-resource"
    end

    # ---- Step (b): RFC 8414 / OIDC discovery → endpoints -----------------------
    def fetch_authorization_server_metadata(issuer)
      guard!(issuer)
      meta = discover_metadata(issuer)
      raise NoAuthServerError, "no authorization-server metadata for issuer" if meta.nil?

      endpoints = {
        issuer: issuer,
        authorization_endpoint: meta["authorization_endpoint"].to_s,
        token_endpoint: meta["token_endpoint"].to_s,
        registration_endpoint: meta["registration_endpoint"].presence,
        # RFC "Client ID Metadata Document": when the AS advertises support, we use
        # our hosted metadata-doc URL as the client_id instead of registering (DCR).
        cimd_supported: meta["client_id_metadata_document_supported"] == true,
        scopes: scope_string(meta["scopes_supported"]),
        raw: meta
      }

      # A malicious ASM can point token_endpoint at http://169.254.169.254/… —
      # guard every endpoint before it is stored or used.
      guard!(endpoints[:authorization_endpoint])
      guard!(endpoints[:token_endpoint])
      guard!(endpoints[:registration_endpoint]) if endpoints[:registration_endpoint].present?

      endpoints
    end

    def discover_metadata(issuer)
      metadata_candidates(issuer).each do |candidate|
        guard!(candidate)
        response = safe_fetch(candidate, allow_statuses: :any)
        next unless response.success?

        parsed = optional_json(response.body)
        return parsed if parsed && parsed["authorization_endpoint"].present? && parsed["token_endpoint"].present?
      end
      nil
    end

    # Metadata URLs to try, in order, for an issuer that may carry a path.
    #
    # RFC 8414 §3.1 INSERTS the well-known segment between host and path
    # ("https://as.example.com/.well-known/oauth-authorization-server/tenant1"),
    # while OpenID Connect Discovery APPENDS it
    # ("https://as.example.com/tenant1/.well-known/openid-configuration").
    # Both are in the wild, so both are tried — spec order first.
    #
    # Only appending is how Airtable went undiscoverable: its issuer is
    # https://airtable.com/oauth2/v1, the appended URL 404s, and the 404 body is
    # a ~300 KB HTML app shell, so the request died on MAX_BYTES and the failure
    # surfaced as "response body exceeds 262144 bytes" rather than "not found".
    def metadata_candidates(issuer)
      uri = URI.parse(issuer)
      path = uri.path.to_s.sub(%r{/\z}, "")
      root = "#{uri.scheme}://#{uri.host}#{":#{uri.port}" if uri.port && uri.port != uri.default_port}"

      inserted =
        if path.present?
          [ "#{root}/.well-known/oauth-authorization-server#{path}",
            "#{root}/.well-known/openid-configuration#{path}" ]
        else
          []
        end

      inserted + [ "#{root}#{path}/.well-known/oauth-authorization-server",
                   "#{root}#{path}/.well-known/openid-configuration" ]
    rescue URI::InvalidURIError
      []
    end

    # ---- Step (c): RFC 7591 dynamic client registration ------------------------
    def register_client(asm, prm)
      cache_metadata(asm[:issuer], prm[:raw], asm[:raw])

      existing = OauthClient.find_by(source: OauthClient::DISCOVERED_SOURCES, issuer: asm[:issuer])
      if existing
        return reuse_client(existing, asm) unless redirect_drifted?(existing)

        # The deployment callback host changed since this DCR client was registered
        # (typically a rotated dev tunnel domain). The redirect_uri is pinned at the
        # AS per client_id, so every authorize would fail with "invalid redirect_uri"
        # — and because the client is keyed by issuer (shared across MCP servers), even
        # a brand-new server pointing at the same AS reuses the poisoned client. Drop
        # the stale registration (dependent: :destroy clears its now-unusable creds) and
        # re-register below. In prod Settings.domain is stable, so this never fires.
        Rails.logger.info("[MCP OAuth] redirect_uri drift for issuer=#{existing.issuer}; re-registering DCR client")
        existing.destroy!
      end

      # Prefer CIMD when the AS supports it: no network round-trip, no registration
      # secret to store, and no per-server DCR row churn — our hosted metadata-doc
      # URL IS the client_id (the AS dereferences it).
      return persist_cimd_client(asm, prm) if asm[:cimd_supported]

      registration_endpoint = asm[:registration_endpoint]
      if registration_endpoint.blank?
        raise RegistrationError.new("authorization server does not support dynamic client registration",
                                    code: RegistrationError::NO_ENDPOINT)
      end

      # A loopback/private registration_endpoint raises UnsafeUrlError here (NOT
      # RegistrationError) so the SSRF signal is preserved.
      guard!(registration_endpoint)
      registration = post_registration(registration_endpoint)
      guard_echoed_uris!(registration)
      persist_dcr_client(asm, prm, registration)
    end

    # Reuse a previously-registered client to avoid re-registering on every
    # connect. Its stored endpoints are attacker-authored, so re-guard them
    # (time-of-use) and refresh them from the freshly discovered + guarded ASM.
    def reuse_client(existing, asm)
      guard!(existing.authorization_endpoint)
      guard!(existing.token_endpoint)
      existing.update!(
        authorization_endpoint: asm[:authorization_endpoint],
        token_endpoint: asm[:token_endpoint],
        registration_endpoint: asm[:registration_endpoint],
        scopes: asm[:scopes]
      )
      existing
    end

    # True only for a DCR client whose registered redirect_uri no longer matches the
    # current deployment callback. CIMD clients never drift (their client_id is our
    # live metadata-doc URL, so the AS reads the current redirect_uris from it), and a
    # client with no recorded redirect (rows from before drift-tracking) reads as current.
    def redirect_drifted?(client)
      return false unless client.source == SOURCE_DCR

      registered = [
        client.metadata["redirect_uri"],
        *Array(client.metadata.dig("dcr", "redirect_uris"))
      ].compact
      registered.any? && registered.exclude?(redirect_uri)
    end

    def post_registration(registration_endpoint)
      # The second deliberate exception to "reject non-2xx" (doctrine rule 4), and
      # the reason is diagnosis: RFC 7591 puts the WHY in a 400 body, and the most
      # common why — the AS approves only loopback callbacks, so a hosted deployment
      # can never self-register — is indistinguishable from a network fault once it
      # has been flattened to "unexpected status=400". The body is still capped by
      # MAX_BYTES, and only an allowlisted code survives #registration_error_code.
      response = safe_fetch(registration_endpoint, method: :post, json: registration_body,
                            allow_statuses: :any)
      unless response.success?
        raise RegistrationError.new("unexpected status=#{response.status}",
                                    code: registration_error_code(response))
      end

      parse_json!(response, RegistrationError)
    rescue FetchError => e
      # Oversize / network from the DCR POST → RegistrationError. UnsafeUrlError (a
      # guard/redirect rejection) is NOT a FetchError, so it propagates unchanged.
      raise RegistrationError, e.message
    end

    # The RFC 7591 error code, or nil for anything the allowlist does not know —
    # including a body that is not JSON, or JSON that is not an object.
    def registration_error_code(response)
      body = optional_json(response.body)
      return nil unless body.is_a?(Hash)

      RegistrationError.known_code(body["error"])
    end

    def registration_body
      {
        client_name: CLIENT_NAME,
        redirect_uris: [ redirect_uri ],
        token_endpoint_auth_method: "none",
        grant_types: %w[authorization_code refresh_token],
        response_types: %w[code]
      }
    end

    # The one deployment-wide callback (identical to Web::OauthController#redirect_uri).
    # This is OUR fixed url, not attacker-derived, so it is not fetched or guarded;
    # only the values a DCR response echoes back are guarded (#guard_echoed_uris!).
    def redirect_uri
      "#{Settings.protocol}://#{Settings.domain}/oauth/callback"
    end

    # RFC 7591 responses may echo back redirect_uris / client_uri; a malicious AS
    # could echo an internal address, so guard any it returns.
    #
    # Except the one we sent. A conforming AS echoes our own redirect_uri back
    # verbatim, and that value is ours — not attacker-derived — so running it
    # through the SSRF guard only ever rejects our own deployment. It did:
    # Supabase (DCR, no CIMD) echoed `https://localhost:4000/oauth/callback` in
    # dev and the whole connect failed with "unsafe url (host=localhost)". The
    # same would happen on any self-hosted install whose domain is a private or
    # loopback host — which, for a self-hostable product, is not an edge case.
    #
    # Anything the AS adds of its own is still guarded, so an echo containing an
    # extra internal URI is still refused.
    def guard_echoed_uris!(registration)
      ours = redirect_uri
      Array(registration["redirect_uris"]).each { |uri| guard!(uri) unless uri == ours }
      guard!(registration["client_uri"]) if registration["client_uri"].present?
    end

    # CIMD: no registration call. Our hosted, publicly-fetchable client-metadata
    # document URL is used verbatim as the client_id; the AS dereferences it to
    # learn our redirect_uris/grant_types. The client is public (PKCE-only), so no
    # client_secret is stored. (Served by Web::OauthController#client_metadata.)
    def persist_cimd_client(asm, prm)
      client_id = client_id_metadata_document_url
      client = OauthClient.find_or_initialize_by(issuer: asm[:issuer], client_id: client_id)
      client.source = SOURCE_CIMD
      client.authorization_endpoint = asm[:authorization_endpoint]
      client.token_endpoint = asm[:token_endpoint]
      client.registration_endpoint = asm[:registration_endpoint]
      client.scopes = asm[:scopes]
      client.metadata = { "prm" => prm[:raw], "asm" => asm[:raw], "cimd" => { "client_id" => client_id } }
      client.save!
      client
    end

    # Our deployment-wide client-metadata document URL — a stable, public endpoint.
    # This IS the CIMD client_id, so it must match the URL the endpoint is served at.
    def client_id_metadata_document_url
      "#{Settings.protocol}://#{Settings.domain}/oauth/client-metadata.json"
    end

    def persist_dcr_client(asm, prm, registration)
      client_id = registration["client_id"].to_s
      raise RegistrationError, "registration response missing client_id" if client_id.blank?

      client = OauthClient.find_or_initialize_by(issuer: asm[:issuer], client_id: client_id)
      client.source = SOURCE_DCR
      client.authorization_endpoint = asm[:authorization_endpoint]
      client.token_endpoint = asm[:token_endpoint]
      client.registration_endpoint = asm[:registration_endpoint]
      client.scopes = asm[:scopes]
      client.metadata = build_metadata(prm, asm, registration)
      # PKCE-only public clients get no secret (confidential? stays false); store
      # one via the encrypted setter only when the AS issues a confidential client.
      secret = registration["client_secret"].presence
      client.client_secret = secret if secret
      client.save!
      client
    end

    # Audit trail of the raw metadata, with bearer-capable DCR fields scrubbed —
    # the metadata column is PLAINTEXT jsonb; the secret lives encrypted elsewhere.
    def build_metadata(prm, asm, registration)
      {
        "prm" => prm[:raw],
        "asm" => asm[:raw],
        "dcr" => registration.except(*SENSITIVE_DCR_KEYS),
        # The callback we registered THIS client with. The AS pins it, so if the
        # deployment domain later changes (e.g. a rotated dev tunnel) we can detect
        # the drift and re-register instead of reusing a client whose authorize
        # would fail with "invalid redirect_uri" (see #redirect_drifted?).
        "redirect_uri" => redirect_uri
      }
    end

    def cache_metadata(issuer, prm_raw, asm_raw)
      key = "mcp_oauth_meta:#{Digest::SHA256.hexdigest(issuer)}"
      Rails.cache.write(key, { "prm" => prm_raw, "asm" => asm_raw }, expires_in: METADATA_CACHE_TTL)
    rescue StandardError => e
      Rails.logger.warn("[MCP::OauthDiscovery] metadata cache write failed: #{e.class}")
    end

    # ---- The one SSRF choke point ----------------------------------------------
    def guard!(url)
      errors = UrlSafetyValidator.errors_for(url, require_https: true)
      raise UnsafeUrlError, "unsafe url (host=#{log_host(url)}): #{errors.first}" if errors.any?

      url
    end

    # GET/POST with: guard! on entry, redirects OFF (followed manually with a
    # per-hop re-guard, capped at MAX_REDIRECTS), TIMEOUT timeouts, MAX_BYTES body
    # cap, status-only errors. Every network call in this file routes through here;
    # there is no un-guarded Net::HTTP.
    def safe_fetch(url, method: :get, json: nil, allow_statuses: nil, accept: DEFAULT_ACCEPT)
      current_url = url
      current_method = method
      current_json = json
      hops = 0

      loop do
        guard!(current_url)
        response = raw_request(current_url, current_method, current_json, accept)
        return validate_status!(response, allow_statuses) unless redirect?(response.status)

        hops += 1
        raise FetchError, "too many redirects (> #{MAX_REDIRECTS})" if hops > MAX_REDIRECTS

        location = response.header("location")
        raise FetchError, "redirect missing Location" if location.blank?

        current_url = URI.join(current_url, location).to_s
        unless METHOD_PRESERVING_REDIRECTS.include?(response.status)
          current_method = :get
          current_json = nil
        end
      end
    end

    def raw_request(url, method, json, accept)
      uri = URI.parse(url)
      http = build_http(uri)
      request = build_request(uri, method, json, accept)

      net_response = nil
      body = +""
      http.request(request) do |res|
        net_response = res
        # Redirect bodies are irrelevant; only read (capped) on a final response.
        unless redirect?(res.code.to_i)
          res.read_body do |chunk|
            body << chunk
            raise FetchError, "response body exceeds #{MAX_BYTES} bytes" if body.bytesize > MAX_BYTES
          end
        end
      end

      Response.new(net_response.code.to_i, net_response, body)
    rescue FetchError, UnsafeUrlError
      raise
    rescue URI::InvalidURIError
      raise FetchError, "invalid url"
    rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError,
           Net::OpenTimeout, Net::ReadTimeout, Net::ProtocolError, IOError, EOFError => e
      raise FetchError, e.class.name
    end

    def build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      pin_public_ip!(http, uri.host)
      http
    end

    # Best-effort DNS pinning (SSRF doctrine rule 6). Pin the pre-validated public
    # IPv4 so the HTTP client cannot re-resolve the hostname into private space
    # between guard! and connect (TOCTOU). Never pins a literal IP host (nothing to
    # re-resolve) and degrades to the hostname when no public IP is found — the
    # redirect cap + per-hop re-guard remain the backstop.
    def pin_public_ip!(http, host)
      return if ip_literal?(host)

      ip = UrlSafetyValidator.resolve_public_ipv4(host)
      http.ipaddr = ip if ip.present?
    rescue StandardError
      nil
    end

    def build_request(uri, method, json, accept)
      klass = method == :post ? Net::HTTP::Post : Net::HTTP::Get
      request = klass.new(uri)
      request["Accept"] = accept
      request["User-Agent"] = "AixleFlow-MCP-OAuth"
      if json
        request["Content-Type"] = "application/json"
        request.body = json.to_json
      end
      request
    end

    def validate_status!(response, allow_statuses)
      return response if allow_statuses == :any
      return response if response.success?
      return response if Array(allow_statuses).include?(response.status)

      raise FetchError, "unexpected status=#{response.status}"
    end

    def redirect?(status)
      REDIRECT_CODES.include?(status)
    end

    # ---- JSON / URL helpers ----------------------------------------------------
    def parse_json!(response, error_class)
      JSON.parse(response.body)
    rescue JSON::ParserError
      raise error_class, "response was not valid JSON (status=#{response.status})"
    end

    def optional_json(body)
      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def scope_string(supported)
      scopes = Array(supported).map(&:to_s).reject(&:blank?)
      scopes.empty? ? nil : scopes.join(" ")
    end

    # RFC 8707 resource indicator = the canonical MCP url (fragment stripped).
    def canonical_resource
      uri = URI.parse(@mcp_url)
      uri.fragment = nil
      uri.to_s
    end

    def origin(url)
      uri = URI.parse(url)
      base = "#{uri.scheme}://#{uri.host}"
      base += ":#{uri.port}" if uri.port && uri.port != uri.default_port
      base
    end

    def ip_literal?(host)
      IPAddr.new(host.to_s)
      true
    rescue IPAddr::InvalidAddressError
      false
    end

    def log_host(url)
      URI.parse(url.to_s).host || "unknown"
    rescue URI::InvalidURIError
      "invalid"
    end
  end
end
