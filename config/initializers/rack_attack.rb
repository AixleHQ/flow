# frozen_string_literal: true

class Rack::Attack
  cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: Settings.redis.url)

  # Extract the login email from EITHER the flat Inertia shape ({ email: ... })
  # or the Rails-nested shape ({ user: { email: ... } }). The login form posts
  # FLAT params, so keying on user[email] alone (the previous code) always
  # yielded nil and silently disabled the per-email/combo throttles. Returns nil
  # when absent so the discriminator is skipped rather than keyed on "".
  def self.login_email(req)
    (req.params["email"] || req.params.dig("user", "email")).to_s.downcase.presence
  end

  def self.login_request?(req)
    req.post? && req.path == "/login"
  end

  MCP_PATHS = %w[/mcp /action_mcp].freeze

  # Machine endpoints the agent containers post to. ws_auth is absent on purpose:
  # it is Traefik's ForwardAuth, asked once per terminal request.
  AGENT_ENDPOINTS = %w[
    /agents/credentials
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

  def self.member_invite?(req)
    req.post? && (req.path == "/company/members" || req.path.match?(%r{\A/company/members/\d+/resend\z}))
  end

  # Coarse per-IP volumetric cap. Kept generous (not 5/20s) so a shared office /
  # NAT / VPN egress IP with many legitimate users isn't locked out — the real
  # per-account brute-force defense is the login/email + login/combo throttles.
  throttle("login/ip",    limit: 20, period: 20)   { |req| req.ip if login_request?(req) }
  # Throttle login attempts by email
  throttle("login/email", limit: 5,  period: 20)   { |req| login_email(req) if login_request?(req) }
  # Slow brute-force protection: combined IP+email over 1 hour
  throttle("login/combo", limit: 10, period: 3600) do |req|
    email = login_email(req)
    "#{req.ip}:#{email}" if login_request?(req) && email
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

  throttle("csp-reports/ip", limit: 60, period: 60) do |req|
    req.ip if req.post? && req.path == "/csp-violation-report-endpoint"
  end

  # Allow OAuth callbacks without rate limiting
  safelist("allow-oauth") { |req| req.path.start_with?("/auth/") }
end

Rack::Attack.enabled = false if Rails.env.test?
