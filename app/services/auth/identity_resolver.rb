# frozen_string_literal: true

module Auth
  # The ONLY writer of UserIdentity (AD-3, enforced mechanically per AD-15).
  #
  # Identity is (provider, subject), never email. Email may *promote* an
  # assertion to an existing user only under the rules in #promotable?, and a
  # changed email updates the stored address without ever re-linking the
  # identity to a different user — mailbox reassignment does not transfer an
  # account.
  class IdentityResolver
    class NoWorkspaceError < StandardError; end
    # An account with this address exists, but this provider is not allowed to
    # attach itself to it. The person signs in with a method they already have
    # and links this one from inside their session.
    class LinkRequiredError < StandardError; end
    class SuperAdminProviderError < StandardError; end

    # `auto_join:` is false when the caller is LINKING an existing credential
    # rather than completing a sign-in. Domain auto-join is a policy for someone
    # arriving for the first time; running it from a password-set callback would
    # silently create memberships nobody asked for.
    def initialize(assertion, auto_join: true)
      @assertion = assertion
      @auto_join = auto_join
    end

    def resolve
      raise Auth::Method::Failure, "incomplete assertion" unless assertion.valid?

      user = find_by_identity || promote_existing_user || create_user
      enforce_super_admin_password_only!(user)

      # A soft-deleted account resolves but is never linked or auto-joined: the
      # caller refuses it (account_deleted). Creating an identity for an account
      # nobody can sign into would be write-only state.
      return user if user.deleted?

      link_identity(user)
      Auth::DomainAutoJoin.call(user, assertion.email, provider: provider) if @auto_join && assertion.email.present?
      user
    end

    private

    attr_reader :assertion

    def provider = assertion.provider

    def find_by_identity
      UserIdentity.find_by(identity_provider: provider, subject: assertion.subject)&.user
    end

    # AD-19: the platform operator account may authenticate by password alone.
    # Checked after the user is known and before any session is minted.
    def enforce_super_admin_password_only!(user)
      return unless user&.super_admin?
      return if provider.password?

      raise SuperAdminProviderError,
            "super_admin accounts may authenticate by password only (got #{provider.kind})"
    end

    def promote_existing_user
      return nil unless promotable?

      # Deliberately unscoped by deletion: a soft-deleted account must resolve so
      # the caller can refuse it explicitly rather than hitting email uniqueness
      # on a doomed insert.
      User.find_by(email: assertion.email)
    end

    # Promotion trust rules (AD-3, amended):
    #   * the provider must assert email_verified — an absent claim is false;
    #   * AND either the provider is DEPLOYMENT-scoped, meaning this
    #     installation's operator configured it and its claims carry the
    #     operator's own trust, OR it is COMPANY-scoped and the email's domain
    #     is that company's verified domain.
    # A customer-administered connection can therefore never attach an identity
    # to an address outside the domain its owner controls.
    def promotable?
      return false if assertion.email.blank?
      return false unless assertion.email_verified?
      return true if provider.deployment?

      company = provider.company
      company.present? && company.email_domain.to_s.casecmp?(email_domain)
    end

    def email_domain
      assertion.email.to_s.split("@").last.to_s
    end

    def create_user
      # Refusing loudly rather than colliding on email uniqueness: the caller can
      # tell the person exactly what to do instead of showing a generic failure.
      existing = assertion.email.present? ? User.find_by(email: assertion.email) : nil
      if existing
        # A platform operator gets the precise reason, not the generic one: their
        # constraint is the method, not the account (AD-19).
        enforce_super_admin_password_only!(existing)
        raise LinkRequiredError, "an account already exists for #{assertion.email}"
      end

      company = Company.find_by_email_domain(assertion.email.to_s)
      raise NoWorkspaceError if company.nil?

      user = User.new(
        email: assertion.email,
        name: assertion.name.presence || assertion.email.to_s.split("@").first,
        avatar_url: assertion.avatar_url
      )
      user.save!
      user
    end

    def link_identity(user)
      identity = UserIdentity.find_or_initialize_by(identity_provider: provider, subject: assertion.subject)
      identity.user = user
      identity.email = assertion.email
      identity.email_verified = assertion.email_verified?
      identity.last_used_at = Time.current
      identity.save!
      identity
    end
  end
end
