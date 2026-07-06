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
  #      deliberate probe in step (a).
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
    CLIENT_NAME = "Aixle"
    TIMEOUT = 5
    MAX_REDIRECTS = 3
    MAX_BYTES = 256 * 1024
    REDIRECT_CODES = [ 301, 302, 303, 307, 308 ].freeze
    METHOD_PRESERVING_REDIRECTS = [ 307, 308 ].freeze
    # Keys in a DCR response that are bearer-capable / secret and must NEVER land
    # in the plaintext metadata jsonb (client_secret is stored encrypted instead).
    SENSITIVE_DCR_KEYS = %w[client_secret registration_access_token].freeze
    METADATA_CACHE_TTL = 1.hour

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
      # The probe is unauthenticated; a 401 (or anything else) is fine — we only
      # want the WWW-Authenticate hint. Redirects are still followed + re-guarded.
      probe = safe_fetch(@mcp_url, allow_statuses: :any)

      prm_url = resource_metadata_url(probe) || default_prm_url
      guard!(prm_url)
      prm = parse_json!(safe_fetch(prm_url), NoAuthServerError)

      servers = Array(prm["authorization_servers"]).map { |s| s.to_s.strip }.reject(&:blank?)
      raise NoAuthServerError, "protected-resource metadata lists no authorization_servers" if servers.empty?

      servers.each { |server| guard!(server) }

      { authorization_servers: servers, scopes: scope_string(prm["scopes_supported"]), raw: prm }
    end

    # Parse `resource_metadata="https://..."` (quoted or bare) out of a
    # WWW-Authenticate challenge, if present.
    def resource_metadata_url(response)
      header = response.header("www-authenticate")
      return nil if header.blank?

      match = header.match(/resource_metadata\s*=\s*"?([^",\s]+)"?/i)
      match && match[1]
    end

    def default_prm_url
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
      base = issuer.sub(%r{/\z}, "")
      candidates = [
        "#{base}/.well-known/oauth-authorization-server",
        "#{base}/.well-known/openid-configuration"
      ]

      candidates.each do |candidate|
        guard!(candidate)
        response = safe_fetch(candidate, allow_statuses: :any)
        next unless response.success?

        parsed = optional_json(response.body)
        return parsed if parsed && parsed["authorization_endpoint"].present? && parsed["token_endpoint"].present?
      end
      nil
    end

    # ---- Step (c): RFC 7591 dynamic client registration ------------------------
    def register_client(asm, prm)
      cache_metadata(asm[:issuer], prm[:raw], asm[:raw])

      existing = OauthClient.find_by(source: SOURCE_DCR, issuer: asm[:issuer])
      return reuse_client(existing, asm) if existing

      registration_endpoint = asm[:registration_endpoint]
      if registration_endpoint.blank?
        raise RegistrationError, "authorization server does not support dynamic client registration"
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

    def post_registration(registration_endpoint)
      response = safe_fetch(registration_endpoint, method: :post, json: registration_body)
      parse_json!(response, RegistrationError)
    rescue FetchError => e
      # Non-2xx / oversize / network from the DCR POST → RegistrationError.
      # UnsafeUrlError (a guard/redirect rejection) is NOT a FetchError, so it
      # propagates unchanged.
      raise RegistrationError, e.message
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
    def guard_echoed_uris!(registration)
      Array(registration["redirect_uris"]).each { |uri| guard!(uri) }
      guard!(registration["client_uri"]) if registration["client_uri"].present?
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
        "dcr" => registration.except(*SENSITIVE_DCR_KEYS)
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
    def safe_fetch(url, method: :get, json: nil, allow_statuses: nil)
      current_url = url
      current_method = method
      current_json = json
      hops = 0

      loop do
        guard!(current_url)
        response = raw_request(current_url, current_method, current_json)
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

    def raw_request(url, method, json)
      uri = URI.parse(url)
      http = build_http(uri)
      request = build_request(uri, method, json)

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

    def build_request(uri, method, json)
      klass = method == :post ? Net::HTTP::Post : Net::HTTP::Get
      request = klass.new(uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = "Aixle-MCP-OAuth"
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
