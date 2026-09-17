# frozen_string_literal: true

module Auth
  # The ONLY computation of a company's effective authentication set (AD-4).
  #
  #   effective set = deployment allowlist ∩ that company's enabled policies
  #
  # The deployment allowlist is CONFIGURATION, never a row, so a self-hosted
  # operator is never handed a toggle for a provider their instance has no
  # credentials for.
  module PolicyResolver
    module_function

    def deployment_allowlist_kinds
      configured = Settings.auth&.enabled_kinds
      list = configured.is_a?(String) ? configured.split(",") : Array(configured)
      list = Auth::Registry.supported_kinds if list.blank?
      declared = list.map { |kind| kind.to_s.strip }.reject(&:blank?)

      # The ceiling is the intersection of what the operator DECLARED and what
      # the installation can actually complete a sign-in with.
      declared & Auth::DeploymentProviders.configured_kinds
    end

    # Providers a company currently accepts for entry.
    def allowed_providers(company)
      return IdentityProvider.none if company.nil?

      IdentityProvider
        .where(kind: deployment_allowlist_kinds)
        .joins(:company_auth_policies)
        .where(company_auth_policies: { company_id: company.id, enabled: true })
        .where("identity_providers.scope = 'deployment' OR identity_providers.company_id = ?", company.id)
        .distinct
    end

    def allowed_provider_ids(company)
      allowed_providers(company).pluck(:id)
    end

    # AD-5/AD-6: a company is satisfied when the intersection of the session's
    # appended proofs with that company's CURRENTLY enabled providers is
    # non-empty. Computed on read against live rows — never a cache, never a
    # sweep — so disabling a provider voids its proofs on the next request.
    #
    # AD-19: a super_admin bypasses every company policy surface.
    # One EXISTS query, not a pluck-and-intersect: this runs on every request,
    # next to the membership re-validation, so it must not add a query pair to
    # every page load.
    def satisfied?(company:, user_session:, user: nil)
      return true if user&.super_admin?
      return false if company.nil? || user_session.nil?

      UserSessionProof
        .where(user_session_id: user_session.id)
        .joins(identity_provider: :company_auth_policies)
        .where(identity_providers: { kind: deployment_allowlist_kinds })
        .where(company_auth_policies: { company_id: company.id, enabled: true })
        .where("identity_providers.scope = 'deployment' OR identity_providers.company_id = :id", id: company.id)
        .exists?
    end

    # AD-7/AD-16: members who would have no usable method left if the company's
    # enabled set became `prospective_provider_ids`. A member's usable methods
    # are the identities they actually hold. Super admins are never stranded.
    def stranded_members(company, prospective_provider_ids)
      usable = Array(prospective_provider_ids)

      company.company_memberships.active.includes(user: :user_identities).filter_map do |membership|
        user = membership.user
        next if user.nil? || user.super_admin?
        next if (user.user_identities.map(&:identity_provider_id) & usable).any?

        user
      end
    end
  end
end
