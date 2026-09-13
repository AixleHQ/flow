# frozen_string_literal: true

module AzureDevops
  # A named operator app configuration, resolved from Settings only.
  #
  # An installation row stores the KEY ("default"), never a secret and never a
  # path. That is what stops a project administrator from pointing a binding at
  # arbitrary credential material by submitting a string: an unknown key raises
  # rather than falling back to anything.
  class AppConfig
    attr_reader :key, :client_id, :client_secret, :private_key,
                :certificate_thumbprint, :credential_generation

    class << self
      def fetch(key)
        key = key.presence || "default"
        raw = configured_apps[key.to_s]
        raise CredentialActionRequired, "No Azure DevOps app configuration named '#{key}'" if raw.blank?

        new(key: key.to_s, raw: raw)
      end

      # There is no separate on/off setting, on purpose. A boolean beside the
      # credentials can only ever disagree with them: "enabled but not
      # configured" fails at the first Azure call with a confusing error, and
      # "configured but disabled" is a switch somebody has to remember to flip
      # after doing all the real work. So the feature is offered exactly when an
      # operator has set up something that can actually reach Azure.
      #
      # PAT mode counts because its credential is supplied per connection by a
      # user, so there is no deployment configuration to derive it from — it
      # stays an explicit setting because it is a policy decision (those
      # connections act as the token's owner), not a redundant copy of one.
      def enabled?
        pat_mode_enabled? || default_app_usable?
      end

      def default_app_usable?
        fetch("default").usable?
      rescue CredentialActionRequired
        false
      end

      def pat_mode_enabled?
        Settings.azure_devops&.pat_mode_enabled == true
      end

      def resource
        Settings.azure_devops&.resource.presence || "https://app.vssps.visualstudio.com/.default"
      end

      def login_host
        Settings.azure_devops&.login_host.presence || "https://login.microsoftonline.com"
      end

      def api_host
        Settings.azure_devops&.api_host.presence || "https://dev.azure.com"
      end

      def token_refresh_skew
        (Settings.azure_devops&.token_refresh_skew || 300).to_i
      end

      # How long to wait between re-reads while confirming a completion. Azure
      # merges asynchronously, so this is a real waiting loop — configurable
      # rather than a constant so a test can set it to zero instead of stubbing
      # sleep (docs/testing.md R7).
      # Service Hooks are the one inbound part of this integration, so they are
      # only attempted when a publicly reachable base URL is actually
      # configured. Without this a development deployment would create
      # subscriptions pointing at localhost that Azure accepts and can never
      # deliver to, and then go on probation trying.
      # Service Hooks are on when Azure can actually reach us, not when an extra
      # variable happens to be set.
      #
      # This used to be `webhook_base_url.present?` against a setting with no
      # default, while the comment beside it claimed it defaulted to the
      # deployment's domain. So a production deployment with DOMAIN set
      # correctly had Service Hooks silently OFF, and its CI gates always
      # closed on the five-minute sweep with nothing anywhere saying why.
      def webhooks_enabled?
        reachable_from_azure?(webhook_base_url)
      end

      # The deployment's own domain, like every other webhook in the app
      # (`Gitlab::RepositoryService` builds its hook URL the same way). The
      # override exists for the case the default cannot cover: a domain Azure
      # cannot resolve, which in practice means a tunnel in development.
      def webhook_base_url
        Settings.azure_devops&.webhook_base_url.presence ||
          "#{Settings.protocol}://#{Settings.domain}"
      end

      # A subscription pointing at a host Azure cannot resolve is worse than no
      # subscription: Azure accepts it, reports it enabled, and every delivery
      # fails until it is disabled — the same shape of silent failure as an
      # unrecognized event filter. So `localhost:4000` provisions nothing, and
      # the operator is told to set a tunnel URL instead.
      def reachable_from_azure?(url)
        host = URI.parse(url.to_s).host
        return false if host.blank?
        return false unless host.include?(".")
        return false if host.end_with?(".local", ".internal", ".localdomain")

        !host.match?(/\A(127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.)/)
      rescue URI::InvalidURIError
        false
      end

      def completion_poll_interval
        (Settings.azure_devops&.completion_poll_interval || 1.0).to_f
      end

      def open_timeout = (Settings.azure_devops&.open_timeout || 5).to_i
      def read_timeout = (Settings.azure_devops&.read_timeout || 30).to_i

      private

      def configured_apps
        apps = Settings.azure_devops&.apps
        return {} if apps.blank?

        apps.respond_to?(:to_hash) ? apps.to_hash.stringify_keys : {}
      end
    end

    def initialize(key:, raw:)
      raw = raw.respond_to?(:to_hash) ? raw.to_hash.stringify_keys : raw.stringify_keys
      @key = key
      @client_id = raw["client_id"].presence
      @client_secret = raw["client_secret"].presence
      @private_key = raw["private_key"].presence
      @certificate_thumbprint = raw["certificate_thumbprint"].presence
      @credential_generation = raw["credential_generation"].presence || "v1"
    end

    # Certificate first: it is the production credential, and a deployment that
    # has both configured during a migration should already be using the new one.
    def credential_kind
      return :certificate if private_key.present? && certificate_thumbprint.present?
      return :client_secret if client_secret.present?

      :none
    end

    def usable?
      client_id.present? && credential_kind != :none
    end

    def validate!
      raise CredentialActionRequired, "Azure DevOps client_id is not configured" if client_id.blank?
      return if credential_kind != :none

      raise CredentialActionRequired,
            "Azure DevOps app '#{key}' has neither a certificate (private_key + certificate_thumbprint) " \
            "nor a client_secret configured"
    end
  end
end
