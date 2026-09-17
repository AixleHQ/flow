# frozen_string_literal: true

module Auth
  # Provisions the deployment-scoped providers this installation offers, from
  # the configured allowlist (AD-4). Idempotent, so it is safe to call at boot,
  # from a migration, from seeds, or from a test setup.
  module DeploymentProviders
    module_function

    def ensure_all!
      Auth::PolicyResolver.deployment_allowlist_kinds.filter_map do |kind|
        next unless IdentityProvider::DEPLOYMENT_KINDS.include?(kind.to_sym)

        IdentityProvider.deployment!(kind)
      end
    end

    # What this installation can actually complete a sign-in with. AD-4 says a
    # self-hoster must never be handed a toggle for a provider their instance has
    # no credentials for — so availability is DERIVED from configuration, never
    # merely declared in the allowlist.
    def configured_kinds
      all_kinds.select { |kind| configured?(kind) }.map(&:to_s)
    end

    def all_kinds
      IdentityProvider::DEPLOYMENT_KINDS | IdentityProvider::COMPANY_KINDS
    end

    def configured?(kind)
      case kind.to_sym
      # Nothing external to configure: these are this app's own machinery.
      when :password, :passkey, :magic_link, :totp then true
      # A customer's own OIDC connection carries its issuer and client
      # credentials on the row, so nothing at deployment level gates the kind.
      when :oidc then true
      # SAML is different: it runs through the sidecar (AD-8), and an
      # installation without one cannot complete it however many connections a
      # company configures.
      when :saml then Settings.sso_bridge&.url.present?
      # These run through a deployment-level OmniAuth strategy, which cannot be
      # registered without credentials.
      when :google then Settings.google_oauth&.client_id.present?
      when :microsoft then Settings.microsoft_oauth&.client_id.present?
      else false
      end
    end
  end
end
