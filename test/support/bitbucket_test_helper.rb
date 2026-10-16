# frozen_string_literal: true

# Shared setup for the Bitbucket tests. App mode is offered exactly when the
# Forge identity is configured, so `with_bitbucket_settings(app_mode: true)`
# supplies one and the default is a deployment that only offers token mode.
module BitbucketTestHelper
  BITBUCKET_API = "https://api.bitbucket.org/2.0"
  FORGE_APP_ID = "ari:cloud:ecosystem::app/0b1c2d3e-0000-4000-8000-00000000a1f0"
  FORGE_ENVIRONMENT_ID = "6f7e8d9c-0000-4000-8000-0000000000e1"
  FORGE_INSTALL_URL = "https://developer.atlassian.com/console/install/0b1c2d3e?signature=test&product=bitbucket"

  # Replaces the Bitbucket::Api seam with FakeBitbucket::Api. The credential
  # chain in front of it (CredentialProvider) stays real.
  def stub_bitbucket!(fake = FakeBitbucket::Api.new)
    Bitbucket::Api.stubs(:new).returns(fake)
    fake
  end

  def with_bitbucket_settings(app_mode: false, token_min_remaining: 300)
    identity = { app_id: FORGE_APP_ID, environment_id: FORGE_ENVIRONMENT_ID, install_url: FORGE_INSTALL_URL }
    identity = identity.transform_values { "" } unless app_mode
    forge = identity.merge(jwks_url: Bitbucket::AppConfig::DEFAULT_JWKS_URL)
    # Zero, so merge confirmation spends no real seconds (docs/testing.md R7).
    Settings.stubs(:bitbucket).returns(
      Hashie::Mash.new(forge: forge, token_min_remaining: token_min_remaining, merge_poll_interval: 0,
                       open_timeout: 1, read_timeout: 2)
    )
  end
end
