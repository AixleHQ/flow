# frozen_string_literal: true

module Bitbucket
  # Deployment configuration for Bitbucket Cloud. Cloud only, so the hosts are
  # constants: a configurable API host would be one more way to send a
  # workspace token somewhere else.
  module AppConfig
    API_HOST = "https://api.bitbucket.org"
    WEB_HOST = "https://bitbucket.org"
    DEFAULT_JWKS_URL = "https://forge.cdn.prod.atlassian-dev.net/.well-known/jwks.json"

    module_function

    def forge_app_id = forge&.app_id.presence
    def forge_environment_id = forge&.environment_id.presence
    def forge_install_url = forge&.install_url.presence
    def forge_jwks_url = forge&.jwks_url.presence || DEFAULT_JWKS_URL

    # No enable flag: the app is offered exactly when an operator has registered
    # one and told this deployment which app and environment it serves. The
    # install link is optional — Forge shares only an app's production
    # environment, so staging installs through `forge install` and has none.
    def app_mode_enabled?
      [ forge_app_id, forge_environment_id ].all?(&:present?)
    end

    # The OAuth client people connect their own account through
    # (docs/design/bitbucket-user-identity.md §2.1). Both values or the feature is off.
    def oauth_client_id = oauth&.client_id.presence
    def oauth_client_secret = oauth&.client_secret.presence
    def oauth_enabled? = [ oauth_client_id, oauth_client_secret ].all?(&:present?)

    def token_min_remaining = (settings&.token_min_remaining || 300).to_i
    def merge_poll_interval = (settings&.merge_poll_interval || 1.0).to_f
    def open_timeout = (settings&.open_timeout || 5).to_i
    def read_timeout = (settings&.read_timeout || 30).to_i

    def settings = Settings.bitbucket
    def forge = settings&.forge
    def oauth = settings&.oauth
  end
end
