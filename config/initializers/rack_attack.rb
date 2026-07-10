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

  # Allow OAuth callbacks without rate limiting
  safelist("allow-oauth") { |req| req.path.start_with?("/auth/") }
end

Rack::Attack.enabled = false if Rails.env.test?
