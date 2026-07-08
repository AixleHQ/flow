# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header
#
# Currently running in report-only mode. Monitor violations before enforcing.
# Switch config.content_security_policy_report_only to false when ready.

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :https, "https://fonts.gstatic.com", :data
    policy.img_src     :self, :https, :data, :blob
    policy.object_src  :none
    policy.script_src  :self, :https
    policy.style_src   :self, :https, :unsafe_inline, "https://fonts.googleapis.com"
    policy.connect_src :self, :https, "wss://#{Settings.domain}"
    policy.frame_src   :none
    policy.report_uri  "/csp-violation-report-endpoint"
    if Rails.env.development?
      policy.script_src  *policy.script_src, :unsafe_eval
      policy.connect_src *policy.connect_src, "ws://localhost:*", "http://localhost:*"
    end
  end

  # Report violations without enforcing — switch to false after baseline is established.
  config.content_security_policy_report_only = true
end
