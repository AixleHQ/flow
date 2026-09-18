# frozen_string_literal: true

# Integration-test support for the Google OAuth flow. OmniAuth's test mode
# short-circuits the strategy: a request to the callback path injects the
# mocked auth hash into request.env["omniauth.auth"] without any external
# HTTP, so sessions#omniauth runs exactly as in production.
module OmniAuthHelper
  GOOGLE_CALLBACK_PATH = "/auth/google/callback"

  # `email_verified` mirrors what Google actually sends (in the id_token, which
  # the strategy exposes as extra.raw_info). It is load-bearing: identity
  # promotion refuses an assertion without it (AD-3), so a fake that omits it
  # would not exercise the real path.
  def with_mocked_google_auth(email:, name: "OAuth User", uid: "google-uid-123", email_verified: true)
    OmniAuth.config.test_mode = true
    # The provider is registered under the name "google" (see
    # config/initializers/omniauth.rb).
    OmniAuth.config.mock_auth[:google] = OmniAuth::AuthHash.new(
      provider: "google",
      uid: uid,
      info: { email: email, name: name, image: "https://example.com/avatar.png" },
      credentials: { token: "mock-token", refresh_token: "mock-refresh-token" },
      extra: { raw_info: { email: email, email_verified: email_verified } }
    )
    yield
  ensure
    OmniAuth.config.mock_auth[:google] = nil
    OmniAuth.config.test_mode = false
  end

  MICROSOFT_CALLBACK_PATH = "/auth/microsoft/callback"

  # Entra sends the stable object id and the tenant id in the id_token, which the
  # strategy exposes as extra.raw_info. Both are load-bearing: `oid` is the
  # subject (AD-3) and `tid` is what a company connection is pinned to (AD-13).
  def with_mocked_microsoft_auth(email:, name: "Entra User", oid: "entra-oid-1", tid: "tenant-abc")
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:microsoft] = OmniAuth::AuthHash.new(
      provider: "microsoft",
      uid: "#{oid}##{tid}",
      info: { email: email, name: name },
      credentials: { token: "mock-token" },
      extra: { raw_info: { oid: oid, tid: tid, email: email, name: name } }
    )
    yield
  ensure
    OmniAuth.config.mock_auth[:microsoft] = nil
    OmniAuth.config.test_mode = false
  end
end
