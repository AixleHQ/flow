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
      },
      # The GitHub App's user OAuth flow (docs/design/github-user-identity.md §4.1).
      # A GitHub App takes its permissions from the App, so no scopes are requested.
      # A connection is a person's own account: only a User may own one.
      # GitHub names itself `https://github.com/login/oauth` in the `iss` of the
      # authorization response (RFC 9207), not `https://github.com`; the callback
      # compares the two, so the issuer must be that value.
      "github" => {
        issuer: "https://github.com/login/oauth",
        authorization_endpoint: "https://github.com/login/oauth/authorize",
        token_endpoint: "https://github.com/login/oauth/access_token",
        scopes: "",
        settings_key: :github,
        owner_types: %w[User],
        after_connect: "Github::UserConnection"
      },
      # A person's own GitLab account, through the deployment's GitLab OAuth app
      # (docs/design/gitlab-user-identity.md §2.2). The endpoints and the issuer follow
      # GITLAB_ENDPOINT, so a resolver supplies them; the client id and secret are
      # the app's, under other Settings names. The operator's host is trusted for
      # the token call (a self-managed GitLab is often on a private network).
      "gitlab" => {
        endpoints: "Gitlab::UserConnection",
        scopes: "api",
        settings_key: :gitlab,
        client_id_key: :oauth_client_id,
        client_secret_key: :oauth_client_secret,
        owner_types: %w[User],
        after_connect: "Gitlab::UserConnection",
        trust_endpoint_host: true
      }
    }.freeze

    module_function

    def known?(provider)
      REGISTRY.key?(provider.to_s)
    end

    # The registry entry, with the endpoints its resolver names (if any) merged in.
    def config(provider)
      entry = REGISTRY.fetch(provider.to_s)
      resolver = entry[:endpoints]
      resolver ? entry.merge(resolver.constantize.endpoints) : entry
    end

    # Hosts the token call may reach although they resolve privately: the operator's
    # own host, for a provider whose entry says so. Empty for every other provider
    # (and for an MCP one, which is not in the registry).
    def trusted_hosts(provider)
      return [] unless known?(provider)

      cfg = config(provider)
      return [] unless cfg[:trust_endpoint_host]

      host = URI.parse(cfg[:token_endpoint].to_s).host.to_s.downcase
      host.empty? ? [] : [ host ]
    rescue URI::InvalidURIError
      []
    end

    def provider_names
      REGISTRY.keys
    end

    # Whether `owner` may hold a connection to this provider. Providers that do not
    # restrict it (Sentry, Railway) take any owner the controller already authorized.
    def owner_allowed?(provider, owner)
      allowed = REGISTRY.dig(provider.to_s, :owner_types)
      allowed.nil? || allowed.include?(owner.class.name)
    end

    # Runs the provider's hook, if it has one, once a credential is stored. The hook
    # may raise Oauth::TokenExchangeError to fail the connection.
    def after_connect(provider, credential)
      hook = REGISTRY.dig(provider.to_s, :after_connect)
      return unless hook

      hook.constantize.record_identity!(credential)
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
      client_id = creds&.public_send(cfg.fetch(:client_id_key, :client_id)).presence
      raise Oauth::MissingClientConfig, provider.to_s if client_id.blank?

      client = OauthClient.find_or_initialize_by(issuer: cfg[:issuer], client_id: client_id)
      client.authorization_endpoint = cfg[:authorization_endpoint]
      client.token_endpoint = cfg[:token_endpoint]
      client.scopes = cfg[:scopes]
      client.source = "static"
      secret_key = cfg.fetch(:client_secret_key, :client_secret)
      secret = creds.respond_to?(secret_key) ? creds.public_send(secret_key).presence : nil
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
