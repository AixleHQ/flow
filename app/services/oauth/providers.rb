# frozen_string_literal: true

module Oauth
  # Registry of known OAuth providers (Phase 1: Sentry, Railway). Authorization/
  # token endpoints and default scopes are STATIC (hard-coded, trusted); only the
  # per-deployment client_id/secret come from Settings.<settings_key>. #client_for
  # reconciles (find-or-update) a `source: "static"` OauthClient row from that
  # config so the rest of the flow can treat every provider uniformly.
  #
  # SECURITY: endpoints come from this trusted table, never from user input, so
  # the token/authorize hosts cannot be attacker-steered in Phase 1 (SSRF surface
  # opens only with DCR in Phase 3).
  module Providers
    # NOTE: the authorization/token endpoints below are the documented public
    # endpoints; confirm them against each provider's live OAuth app before
    # enabling in production. Providers stay inert until client_id is set, so a
    # wrong endpoint only surfaces at connect time, never at boot. Scopes are
    # space-separated per OAuth 2.1.
    REGISTRY = {
      "sentry" => {
        issuer: "https://sentry.io",
        authorization_endpoint: "https://sentry.io/oauth/authorize/",
        token_endpoint: "https://sentry.io/oauth/token/",
        scopes: "org:read project:read event:read",
        settings_key: :sentry_oauth
      },
      "railway" => {
        issuer: "https://railway.app",
        authorization_endpoint: "https://railway.app/oauth/authorize",
        token_endpoint: "https://backboard.railway.app/oauth/token",
        scopes: "read",
        settings_key: :railway_oauth
      }
    }.freeze

    module_function

    def known?(provider)
      REGISTRY.key?(provider.to_s)
    end

    def config(provider)
      REGISTRY.fetch(provider.to_s)
    end

    def provider_names
      REGISTRY.keys
    end

    # Reconcile and return the OauthClient for a static provider.
    #
    # Raises KeyError for an unknown provider (programmer error — guard with
    # #known? first). Raises Oauth::MissingClientConfig when the provider is known
    # but Settings has no client_id (the operator has not configured it) — callers
    # translate this into a user-facing "not configured" message, never a 500.
    def client_for(provider)
      cfg = config(provider)
      creds = provider_settings(cfg[:settings_key])
      client_id = creds&.client_id.presence
      raise Oauth::MissingClientConfig, provider.to_s if client_id.blank?

      client = OauthClient.find_or_initialize_by(issuer: cfg[:issuer], client_id: client_id)
      client.authorization_endpoint = cfg[:authorization_endpoint]
      client.token_endpoint = cfg[:token_endpoint]
      client.scopes = cfg[:scopes]
      client.source = "static"
      secret = creds.respond_to?(:client_secret) ? creds.client_secret.presence : nil
      client.client_secret = secret if secret
      client.save!
      client
    end

    # Read the provider's Settings block. The `config` gem returns nil for a
    # missing top-level key; the rescue guards a deployment that opts into
    # fail-on-missing so an unconfigured provider still degrades to nil.
    def provider_settings(settings_key)
      Settings.public_send(settings_key)
    rescue NoMethodError, KeyError
      nil
    end
  end
end
