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
