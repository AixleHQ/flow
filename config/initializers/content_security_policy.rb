# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header
#
# Currently running in report-only mode. Monitor violations before enforcing.
# Switch config.content_security_policy_report_only to false when ready.

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

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :https, "https://fonts.gstatic.com", :data
    policy.img_src     :self, :https, :data, :blob
    policy.object_src  :none
    policy.script_src  :self, :https
    policy.style_src   :self, :https, :unsafe_inline, "https://fonts.googleapis.com"
    policy.connect_src :self, :https, "wss://#{Settings.domain}"
    # The onboarding agent-auth terminal and workspace IDE/terminal panels embed
    # ttyd cross-origin (Traefik host), so frame_src must allow that origin — a
    # bare :none would block the core auth flow once CSP is enforced. Still
    # report-only for now; confirm the exact origins from violation reports
    # before flipping report_only to false.
    policy.frame_src   :self, Settings.traefik.http_base
    policy.report_uri  csp_report_uri
    if Rails.env.development?
      policy.script_src  *policy.script_src, :unsafe_eval
      policy.connect_src *policy.connect_src, "ws://localhost:*", "http://localhost:*"
      policy.frame_src   *policy.frame_src, "http://localhost:*"
    end
  end

  # Report violations without enforcing — switch to false after baseline is established.
  config.content_security_policy_report_only = true
end
