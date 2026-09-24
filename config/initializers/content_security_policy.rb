# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

# CSP violations are sent to Sentry's Security Header endpoint (derived from the
# frontend DSN, so it follows per-env config and needs no extra secret) where
# they aggregate as issues. Falls back to the local /csp-violation-report-endpoint
# sink when no DSN is configured (e.g. dev/test).
csp_report_uri =
  begin
    dsn = Settings.sentry.frontend_dsn.to_s
    if dsn.present?
      u = URI.parse(dsn)
      "#{u.scheme}://#{u.host}/api/#{u.path.delete_prefix('/')}/security/?sentry_key=#{u.user}"
    else
      "/csp-violation-report-endpoint"
    end
  rescue URI::InvalidURIError
    "/csp-violation-report-endpoint"
  end

# Scripts come from this origin or the asset host, never from "any https URL";
# the one inline script the app layout needs carries the per-request nonce.
script_hosts = [ :self, Settings.asset_host.presence ].compact

# An enforced policy of the directives no page can trip over (nothing here uses
# <base> or plugins, or is framed by another site), sent while the full policy is
# still report-only. It runs outside Rails' CSP middleware on purpose: that
# middleware adds nothing to a response that already carries a policy, so this
# one is added on the way out, after it.
class StructuralContentSecurityPolicy
  POLICY = "base-uri 'self'; object-src 'none'; frame-ancestors 'self'"

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    headers[ActionDispatch::Constants::CONTENT_SECURITY_POLICY] ||= POLICY
    [ status, headers, body ]
  end
end

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri    :self
    policy.frame_ancestors :self
    policy.font_src    :self, :https, "https://fonts.gstatic.com", :data
    policy.img_src     :self, :https, :data, :blob
    policy.object_src  :none
    policy.script_src(*script_hosts)
    # Mantine writes style attributes at runtime.
    policy.style_src   :self, :https, :unsafe_inline, "https://fonts.googleapis.com"
    # Sentry's session replay compresses in a worker it starts from a blob: URL.
    policy.worker_src  :self, :blob
    policy.connect_src :self, :https, "wss://#{Settings.domain}"
    # The onboarding agent-auth terminal and workspace IDE/terminal panels embed
    # ttyd cross-origin (Traefik host), so frame_src must allow that origin.
    policy.frame_src   :self, Settings.traefik.http_base
    policy.report_uri  csp_report_uri
    if Rails.env.development?
      policy.script_src(*policy.script_src, :unsafe_eval)
      policy.connect_src(*policy.connect_src, "ws://localhost:*", "http://localhost:*")
      policy.frame_src(*policy.frame_src, "http://localhost:*")
    end
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # The whole policy is enforced once CSP_ENFORCE=true; until then it only reports.
  config.content_security_policy_report_only = !Settings.security.csp_enforce
  config.middleware.insert_before ActionDispatch::ContentSecurityPolicy::Middleware, StructuralContentSecurityPolicy
end
