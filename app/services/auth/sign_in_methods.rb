# frozen_string_literal: true

module Auth
  # The person's own sign-in methods, as Profile → Security manages them: which
  # redirect providers they may link, and whether one may be removed.
  module SignInMethods
    LINKABLE_KINDS = %w[google microsoft].freeze
    # Password, passkey and emailed-link identities are re-created by their next
    # use, so removing the row would remove nothing. Those are managed by their
    # own credential (a passkey, the password) instead.
    REMOVABLE_KINDS = %w[google microsoft oidc].freeze

    class RemovalRefused < StandardError; end

    module_function

    # Offered only where linking can finish: this installation has the provider
    # configured and allowed, and a company the person belongs to accepts it —
    # a method no company of theirs accepts would be a way in to nowhere.
    def linkable_kinds(user)
      return [] if user.super_admin?

      accepted = Auth::PolicyResolver.accepted_kinds(
        company_ids: user.company_memberships.active.select(:company_id), kinds: LINKABLE_KINDS
      )
      LINKABLE_KINDS & accepted
    end

    def linkable?(user, kind)
      linkable_kinds(user).include?(kind.to_s)
    end

    # @return [String, nil] why `identity` may not be removed, in words for the person
    def removal_refusal(user, identity)
      name = identity.identity_provider.display_name
      return "#{name} is managed from its own section, not here." unless REMOVABLE_KINDS.include?(identity.kind.to_s)
      return "#{name} is your only way to sign in." if user.user_identities.where.not(id: identity.id).none?

      stranded = Auth::PolicyResolver.companies_stranded_without(user, identity)
      return nil if stranded.empty?

      names = stranded.map(&:branded_name).to_sentence
      "#{name} is your only sign-in method that #{names} #{stranded.one? ? 'accepts' : 'accept'}. " \
        "Link another method #{stranded.one? ? 'it accepts' : 'they accept'} first."
    end

    # Checked and removed under a lock on the user, so two removals racing from
    # two tabs cannot each pass the check and together strand them (AD-7).
    def remove!(user, identity)
      user.with_lock do
        refusal = removal_refusal(user, identity)
        raise RemovalRefused, refusal if refusal

        Auth::IdentityResolver.unlink(identity)
      end
    end
  end
end
