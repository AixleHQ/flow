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
    # one and told this deployment which app and environment it serves.
    def app_mode_enabled?
      [ forge_app_id, forge_environment_id, forge_install_url ].all?(&:present?)
    end

    def token_min_remaining = (settings&.token_min_remaining || 300).to_i
    def merge_poll_interval = (settings&.merge_poll_interval || 1.0).to_f
    def open_timeout = (settings&.open_timeout || 5).to_i
    def read_timeout = (settings&.read_timeout || 30).to_i

    def settings = Settings.bitbucket
    def forge = settings&.forge
  end
end
