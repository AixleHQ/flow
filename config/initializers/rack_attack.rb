# frozen_string_literal: true

# Every discriminator below runs in middleware, ahead of routing, on every
# request: anything one raises answers 500 on every url in the app, so a
# discriminator reads the request defensively and skips what it cannot key on.
class Rack::Attack
  cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: Settings.redis.url)

  # Extract the login email from EITHER the flat Inertia shape ({ email: ... })
  # or the Rails-nested shape ({ user: { email: ... } }). The login form posts
  # FLAT params, so keying on user[email] alone (the previous code) always
  # yielded nil and silently disabled the per-email/combo throttles. Returns nil
  # when absent so the discriminator is skipped rather than keyed on "".
  def self.login_email(req)
    p = params_with_json(req)
    (string_param(p, "email") || string_param(p, "user", "email")).to_s.downcase.presence
  end

  JSON_BODY_LIMIT = 16_384

  # `req.params` parses the query string and form-encoded bodies but NOT a JSON
  # body; the login and magic-link actions read JSON too (a JSON login succeeds),
  # so a throttle keyed only on `req.params` was bypassable by sending the request
  # as application/json — the per-email and per-combo discriminators saw nil and
  # were silently skipped. Merge a bounded, rewound parse of the JSON body so the
  # throttles see the address whatever the content type. The body is rewound after
  # reading, so the app downstream still parses it.
  def self.params_with_json(req)
    json = json_body(req)
    params = safe_params(req)
    json.empty? ? params : params.merge(json)
  end

  def self.json_body(req)
    return {} unless req.content_type.to_s.include?("application/json")

    body = req.body
    return {} unless body

    raw = body.read(JSON_BODY_LIMIT + 1)
    body.rewind
    return {} if raw.nil? || raw.bytesize > JSON_BODY_LIMIT

    parsed = JSON.parse(raw)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError, IOError, NoMethodError
    {}
  end

  # The caller controls the shape as well as the value ("?user=x" is a String,
  # "?user[]=x" an Array). Only a String leaf can be an address; any other shape
  # reads as absent, which also keeps "?email[]=a@b.test" from earning a bucket
  # separate from "?email=a@b.test".
  def self.string_param(params, *path)
    value = params
    path.each do |key|
      return nil unless value.is_a?(Hash)

      value = value[key]
    end
    value if value.is_a?(String)
  end

  # Rack::BadRequest marks the query strings Rack refuses to decode
  # ("?user=x&user[a]=1", invalid %-encoding, nesting past its limit). Rails
  # answers 400 for that family downstream, and undecodable input carries no
  # address.
  def self.safe_params(req)
    req.params
  rescue Rack::BadRequest
    {}
  end

  LOGIN_PATHS = %w[/login /admin/login].freeze

  def self.login_request?(req)
    req.post? && LOGIN_PATHS.include?(req.path)
  end

  MCP_PATHS = %w[/mcp /action_mcp].freeze

  # Machine endpoints the agent containers post to. ws_auth is absent on purpose:
  # it is Traefik's ForwardAuth, asked once per terminal request.
  AGENT_ENDPOINTS = %w[
    /agents/credentials
    /agents/credentials/refresh
    /agents/git/credentials
    /azure/git/credentials
    /cloud/aws/credentials
    /api/v1/internal/usage_statistics
  ].freeze

  # A digest, so the throttle's cache keys never hold a live credential.
  def self.mcp_credential(req)
    key = req.get_header("HTTP_X_SESSION_KEY").presence ||
          req.get_header("HTTP_AUTHORIZATION").to_s.delete_prefix("Bearer ").presence
    Digest::SHA256.hexdigest(key)[0, 32] if key
  end

  # A digest, so the throttle's cache keys never hold a live credential.
  def self.scim_credential(req)
    token = req.get_header("HTTP_AUTHORIZATION").to_s.delete_prefix("Bearer ").presence
    Digest::SHA256.hexdigest(token)[0, 32] if token
  end

  RUNNER_GATEWAY_PREFIX = "/runner/v1/"

  def self.runner_gateway?(req)
    req.path.start_with?(RUNNER_GATEWAY_PREFIX)
  end

  # A digest, so the throttle's cache keys never hold a live credential.
  def self.runner_credential(req)
    token = req.get_header("HTTP_AUTHORIZATION").to_s.delete_prefix("Bearer ").presence
    Digest::SHA256.hexdigest(token)[0, 32] if token
  end

  def self.scim?(req)
    req.path == "/scim" || req.path.start_with?("/scim/")
  end

  def self.member_invite?(req)
    req.post? && (req.path == "/company/members" || req.path.match?(%r{\A/company/members/\d+/resend\z}))
  end

  # Step-up re-verifies the account password inside an ALREADY authenticated
  # session, so it is a second password oracle and needs its own throttle: a
  # hijacked or low-privilege session could otherwise brute-force the account's
  # password against it without ever touching /login.
  def self.step_up_request?(req)
    req.post? && req.path == "/step_up"
  end

  # Every other endpoint that accepts or issues a credential. A magic-link
  # request in particular sends mail to an arbitrary address, so without a
  # throttle it is a mail-bombing tool; the rest are cheap to script against.
  def self.credential_request?(req)
    return false unless req.post?

    req.path == "/login/magic" ||
      req.path == "/login/sso" ||
      req.path == "/login/passkey" ||
      req.path == "/login/passkey/options" ||
      req.path.match?(%r{\A/auth/oidc/\d+/start\z})
  end

  # Coarse per-IP volumetric cap. Kept generous (not 5/20s) so a shared office /
  # NAT / VPN egress IP with many legitimate users isn't locked out — the real
  # per-account brute-force defense is the login/email + login/combo throttles.
  throttle("login/ip",    limit: 20, period: 20)   { |req| req.ip if login_request?(req) }
  # Throttle login attempts by email
  throttle("login/email", limit: 5,  period: 20)   { |req| login_email(req) if login_request?(req) }
  # Slow brute-force protection: combined IP+email over 1 hour
  throttle("step_up/ip", limit: 10, period: 60) { |req| req.ip if step_up_request?(req) }
  throttle("credential/ip", limit: 20, period: 60) { |req| req.ip if credential_request?(req) }
  # Mail specifically: one address must not be reachable at volume from many IPs.
  throttle("magic_link/email", limit: 5, period: 300) do |req|
    string_param(params_with_json(req), "email").to_s.downcase.presence if req.post? && req.path == "/login/magic"
  end

  # The path check first, so only sign-in requests have their params and body
  # parsed.
  throttle("login/combo", limit: 10, period: 3600) do |req|
    next unless login_request?(req)

    email = login_email(req)
    "#{req.ip}:#{email}" if email
  end

  # The limits below cover what answers without a signed-in user. They sit far
  # above legitimate use: they cap floods and guessing, nothing a working client
  # can reach.

  # An agent makes an MCP call per tool use, a few a second when busy.
  throttle("mcp/credential", limit: 600, period: 60) { |req| mcp_credential(req) if MCP_PATHS.include?(req.path) }
  throttle("mcp/ip", limit: 1200, period: 60) { |req| req.ip if MCP_PATHS.include?(req.path) }

  throttle("agent-endpoints/ip", limit: 600, period: 60) do |req|
    req.ip if req.post? && AGENT_ENDPOINTS.include?(req.path)
  end

  # Providers burst and retry. A generic source gets its own, lower cap: every
  # delivery it gets accepted can start a workflow run.
  throttle("webhooks/ip", limit: 600, period: 60) { |req| req.ip if req.post? && req.path.start_with?("/webhooks/") }
  throttle("webhooks/ingress", limit: 60, period: 60) do |req|
    req.path if req.post? && req.path.start_with?("/webhooks/in/")
  end

  throttle("share/ip", limit: 300, period: 60) { |req| req.ip if req.path.start_with?("/share/") }

  # An invitation link is a bearer token, and signing up through one sets a password.
  throttle("invitations/ip", limit: 30, period: 60) { |req| req.ip if req.path.start_with?("/invitations/") }

  # Each invite sends an email to an address the inviter typed.
  throttle("member-invites/session", limit: 60, period: 3600) do |req|
    req.session["user_session_id"].presence if member_invite?(req)
  end

  # A customer's directory reaches SCIM with a bearer token and nothing else, and
  # on a deployment that publishes the endpoint that token is the only thing
  # between the internet and a company's membership list. Two throttles: one per
  # credential, generous enough for a real directory's reconciliation sweep, and
  # one per IP that caps guessing at an unusable rate.
  throttle("scim/credential", limit: 600, period: 60) { |req| scim_credential(req) if scim?(req) }
  throttle("scim/ip", limit: 60, period: 60) { |req| req.ip if scim?(req) }

  # A runner long-polls (one request per 25 s at rest) and posts logs and
  # results while a session runs, a few a second at most. Registering is once
  # per machine, so its per-IP cap only has to allow a fleet set up from one
  # egress address.
  throttle("runner-gateway/credential", limit: 600, period: 60) do |req|
    runner_credential(req) if runner_gateway?(req)
  end
  throttle("runner-gateway/register/ip", limit: 30, period: 60) do |req|
    req.ip if req.post? && req.path == "#{RUNNER_GATEWAY_PREFIX}register"
  end

  throttle("csp-reports/ip", limit: 60, period: 60) do |req|
    req.ip if req.post? && req.path == "/csp-violation-report-endpoint"
  end

  # Callbacks only. The safelist used to cover the whole /auth/ prefix, which
  # silently exempted the OIDC *start* action — an endpoint a person triggers,
  # not an identity provider.
  safelist("allow-oauth-callbacks") do |req|
    req.path.match?(%r{\A/auth/[^/]+/callback\z}) || req.path == "/auth/oidc/callback" ||
      req.path == "/auth/failure"
  end
end

Rack::Attack.enabled = false if Rails.env.test?
