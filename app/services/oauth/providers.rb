# frozen_string_literal: true

module Oauth
  # Registry of known OAuth providers (Phase 1: Sentry, Railway). Authorization/
  # token endpoints and default scopes are STATIC (hard-coded, trusted) or named by
  # an `endpoints` callable of the deployment's own config; only the per-deployment
  # client id and secret come from the entry's `oauth_app` callable. #client_for
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
        oauth_app: -> { app_from_settings(:sentry_oauth) }
      },
      "railway" => {
        issuer: "https://railway.app",
        authorization_endpoint: "https://railway.app/oauth/authorize",
        token_endpoint: "https://backboard.railway.app/oauth/token",
        scopes: "read",
        oauth_app: -> { app_from_settings(:railway_oauth) }
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
        oauth_app: -> { app_from_settings(:github) },
        owner_types: %w[User],
        fetch_identity: ->(access_token) { Github::UserConnection.fetch_identity(access_token) }
      },
      # A person's own GitLab account, through the deployment's GitLab OAuth app
      # (docs/design/gitlab-user-identity.md §2.2). The endpoints and the issuer follow
      # GITLAB_ENDPOINT, so `endpoints` supplies them (the revocation endpoint too, which
      # the engine posts to when the person disconnects); the client id and secret are
      # the GitLab app's. The operator's host is trusted for the token call (a
      # self-managed GitLab is often on a private network).
      "gitlab" => {
        endpoints: -> { Gitlab::UserConnection.endpoints },
        scopes: "api",
        oauth_app: -> {
          { client_id: Gitlab::AppConfig.oauth_client_id, client_secret: Gitlab::AppConfig.oauth_client_secret }
        },
        owner_types: %w[User],
        fetch_identity: ->(access_token) { Gitlab::UserConnection.fetch_identity(access_token) },
        trust_endpoint_host: true
      },
      # A person's own Bitbucket Cloud account, through the deployment's OAuth client
      # (docs/design/bitbucket-user-identity.md §2.3). Cloud only, so the hosts are fixed.
      # The client scopes are set on the client itself and cannot be narrowed per grant,
      # so none is requested. Bitbucket authenticates the client with HTTP Basic, and
      # offers no revocation endpoint.
      "bitbucket" => {
        issuer: Bitbucket::AppConfig::WEB_HOST,
        authorization_endpoint: "#{Bitbucket::AppConfig::WEB_HOST}/site/oauth2/authorize",
        token_endpoint: "#{Bitbucket::AppConfig::WEB_HOST}/site/oauth2/access_token",
        scopes: "",
        oauth_app: -> {
          { client_id: Bitbucket::AppConfig.oauth_client_id, client_secret: Bitbucket::AppConfig.oauth_client_secret }
        },
        owner_types: %w[User],
        client_auth: :basic,
        fetch_identity: ->(access_token) { Bitbucket::UserConnection.fetch_identity(access_token) }
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
      resolver ? entry.merge(resolver.call) : entry
    end

    # How the client authenticates at the token endpoint: `:post` (client_id and
    # client_secret in the form body, the default) or `:basic` (RFC 6749 §2.3.1, HTTP
    # Basic, with nothing of the client in the body).
    def client_auth(provider)
      REGISTRY.dig(provider.to_s, :client_auth) || :post
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

    # The account's identity for a person's own connection, fetched with the new access
    # token BEFORE the credential is stored: { metadata_key => identity }, to be stored
    # with the token in one save. nil for a provider with no such hook (Sentry, Railway,
    # MCP servers). Raises Oauth::TokenExchangeError when the identity cannot be fetched,
    # which fails the connection with nothing stored and the previous credential untouched.
    def fetch_identity(provider, access_token)
      hook = REGISTRY.dig(provider.to_s, :fetch_identity)
      return unless hook

      { OauthCredential::IDENTITY_FIELDS.fetch(provider.to_s).fetch(:metadata_key) => hook.call(access_token) }
    end

    # The issuer and client id the deployment is configured with now for a static
    # provider, or nil when it has no client id. Reads the settings only: it creates no
    # OauthClient row (#client_for does).
    def current_client_ref(provider)
      cfg = config(provider)
      client_id = cfg.fetch(:oauth_app).call[:client_id].presence
      client_id && { issuer: cfg[:issuer], client_id: client_id }
    end

    # Reconcile and return the OauthClient for a static provider.
    #
    # Raises KeyError for an unknown provider (programmer error — guard with
    # #known? first). Raises Oauth::MissingClientConfig when the provider is known
    # but Settings has no client_id (the operator has not configured it) — callers
    # translate this into a user-facing "not configured" message, never a 500.
    def client_for(provider)
      cfg = config(provider)
      app = cfg.fetch(:oauth_app).call
      client_id = app[:client_id].presence
      raise Oauth::MissingClientConfig, provider.to_s if client_id.blank?

      client = OauthClient.find_or_initialize_by(issuer: cfg[:issuer], client_id: client_id)
      client.authorization_endpoint = cfg[:authorization_endpoint]
      client.token_endpoint = cfg[:token_endpoint]
      client.scopes = cfg[:scopes]
      client.source = "static"
      secret = app[:client_secret].presence
      client.client_secret = secret if secret
      client.save!
      client
    end

    # The client id and secret in a Settings block. The `config` gem returns nil for a
    # missing top-level key; the rescue guards a deployment that opts into
    # fail-on-missing so an unconfigured provider still degrades to nil values.
    def app_from_settings(settings_key)
      settings = begin
        Settings.public_send(settings_key)
      rescue NoMethodError, KeyError
        nil
      end
      return { client_id: nil, client_secret: nil } unless settings

      { client_id: settings.client_id, client_secret: settings.respond_to?(:client_secret) ? settings.client_secret : nil }
    end
  end
end
