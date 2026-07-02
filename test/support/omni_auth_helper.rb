# frozen_string_literal: true

# Integration-test support for the Google OAuth flow. OmniAuth's test mode
# short-circuits the strategy: a request to the callback path injects the
# mocked auth hash into request.env["omniauth.auth"] without any external
# HTTP, so sessions#omniauth runs exactly as in production.
module OmniAuthHelper
  GOOGLE_CALLBACK_PATH = "/auth/google/callback"

  def with_mocked_google_auth(email:, name: "OAuth User", uid: "google-uid-123")
    OmniAuth.config.test_mode = true
    # The provider is registered under the name "google" (see
    # config/initializers/omniauth.rb).
    OmniAuth.config.mock_auth[:google] = OmniAuth::AuthHash.new(
      provider: "google",
      uid: uid,
      info: { email: email, name: name, image: "https://example.com/avatar.png" },
      credentials: { token: "mock-token", refresh_token: "mock-refresh-token" }
    )
    yield
  ensure
    OmniAuth.config.mock_auth[:google] = nil
    OmniAuth.config.test_mode = false
  end
end
