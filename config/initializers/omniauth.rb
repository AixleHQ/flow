# frozen_string_literal: true

require_relative "../../lib/omniauth/strategies/microsoft"

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, Settings.google_oauth.client_id, Settings.google_oauth.client_secret, {
    scope: "email,profile",
    prompt: "select_account",
    image_aspect_ratio: "square",
    image_size: 50,
    access_type: "offline",
    name: "google"
  }

  # Registered only when this installation actually has Microsoft credentials.
  # A strategy without them answers every request with a redirect to a broken
  # consent screen, which is worse than not offering the button at all — and
  # Auth::DeploymentProviders.configured_kinds asks the same question.
  microsoft = Settings.microsoft_oauth
  if OmniAuth::Strategies::Microsoft.configured?(microsoft)
    provider OmniAuth::Strategies::Microsoft, {
      client_id: microsoft.client_id,
      client_secret: microsoft.client_secret.presence,
      private_key: microsoft.private_key.presence,
      certificate_thumbprint: microsoft.certificate_thumbprint.presence,
      tenant_id: microsoft.tenant_id.presence || "common"
    }
  end
end

# CVE-2015-9284: OmniAuth's request phase must be POST-only, or an attacker
# can trigger a login/link flow on a victim's session via a plain GET link
# (CSRF). Leave allowed_request_methods at its :post-only default — the
# login button submits a real <form method="post"> (GoogleLoginButton.tsx).
OmniAuth.config.path_prefix = "/auth"

# Set failure path
OmniAuth.config.on_failure = Proc.new { |env|
  OmniAuth::FailureEndpoint.new(env).redirect_to_failure
}
