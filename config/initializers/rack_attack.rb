# frozen_string_literal: true

class Rack::Attack
  cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: Settings.redis.url)

  # Throttle login attempts by IP
  throttle("login/ip",    limit: 5,  period: 20)   { |r| r.ip                                                                    if r.path == "/login" && r.post? }
  # Throttle login attempts by email
  throttle("login/email", limit: 5,  period: 20)   { |r| r.params.dig("user", "email")&.downcase                                if r.path == "/login" && r.post? }
  # Slow brute-force protection: combined IP+email over 1 hour
  throttle("login/combo", limit: 10, period: 3600) { |r| "#{r.ip}:#{r.params.dig('user', 'email')&.downcase}"                  if r.path == "/login" && r.post? }

  # Allow OAuth callbacks without rate limiting
  safelist("allow-oauth") { |r| r.path.start_with?("/auth/") }
end
