# frozen_string_literal: true

module Auth
  # Applies a company's auth-policy change under the AD-7 guard.
  #
  # Three failure modes this exists to prevent, all of them observed as real
  # incidents in other products:
  #   * enabling a connection nobody has ever signed in through, then finding out
  #     it was misconfigured only once everyone is locked out;
  #   * deleting a connection instead of disabling it, and slipping past a guard
  #     that only reads `enabled`;
  #   * two individually-safe edits racing to an empty effective set.
  #
  # The guard covers EVERY active member, not merely the acting admin: otherwise
  # one compromised admin can strip everyone else's access without tripping it.
  class PolicyUpdater
    class Refused < StandardError
      attr_reader :reason, :stranded

      def initialize(message, reason:, stranded: [])
        super(message)
        @reason = reason
        @stranded = stranded
      end
    end

    def initialize(company:, actor:, auth_session: nil)
      @company = company
      @actor = actor
      @auth_session = auth_session
    end

    # @param provider [IdentityProvider]
    # @param enabled [Boolean]
    def set(provider, enabled:)
      company.with_lock do
        policy = CompanyAuthPolicy.find_or_initialize_by(company: company, identity_provider: provider)
        return policy if policy.persisted? && policy.enabled == enabled

        guard_activation!(provider) if enabled
        guard_no_stranding!(provider, enabled)
        guard_actor_still_admitted!(provider, enabled)

        policy.enabled = enabled
        policy.save!
        policy
      end
    end

    # Deleting a connection is evaluated exactly as disabling it.
    def remove(provider)
      company.with_lock do
        guard_no_stranding!(provider, false)
        guard_actor_still_admitted!(provider, false)
        CompanyAuthPolicy.where(company: company, identity_provider: provider).destroy_all
        provider.destroy! if provider.company_id == company.id
        true
      end
    end

    private

    attr_reader :company, :actor, :auth_session

    # Prove before you enforce: a company-scoped connection may only be switched
    # on once an admin of this company has completed a real sign-in through it.
    # Deployment-scoped providers are operator-configured and exempt.
    def guard_activation!(provider)
      return if actor&.super_admin?
      return if provider.deployment?

      admin_user_ids = company.company_memberships.active.where(role: "admin").select(:user_id)
      proved = UserIdentity.where(identity_provider: provider, user_id: admin_user_ids).exists?
      return if proved

      raise Refused.new(
        "no administrator of #{company.name} has signed in through #{provider.display_name} yet",
        reason: :not_proved
      )
    end

    # AD-7 rule 4: the acting admin must still hold a proof this company accepts
    # AFTER the edit. Enforced only when the caller supplied the live session —
    # a console or rake caller has no session to check, and refusing those
    # outright would make the guard unusable for operations.
    def guard_actor_still_admitted!(provider, enabled)
      return if actor&.super_admin?
      return if auth_session.nil?

      prospective = prospective_provider_ids(provider, enabled)
      return if (auth_session.proved_provider_ids & prospective).any?

      raise Refused.new(
        "this change would leave your own session unable to re-enter #{company.name}",
        reason: :would_lock_out_actor
      )
    end

    def guard_no_stranding!(provider, enabled)
      prospective = prospective_provider_ids(provider, enabled)
      stranded = Auth::PolicyResolver.stranded_members(company, prospective)
      return if stranded.empty?
      return if actor&.super_admin?

      raise Refused.new(
        "this change would leave #{stranded.size} member(s) with no way to sign in",
        reason: :would_strand, stranded: stranded
      )
    end

    def prospective_provider_ids(provider, enabled)
      current = Auth::PolicyResolver.allowed_provider_ids(company)
      enabled ? (current | [ provider.id ]) : (current - [ provider.id ])
    end
  end
end
