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
    req.params["email"].to_s.downcase.presence if req.post? && req.path == "/login/magic"
  end

  throttle("login/combo", limit: 10, period: 3600) do |req|
    email = login_email(req)
    "#{req.ip}:#{email}" if login_request?(req) && email
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
