# frozen_string_literal: true

module Auth
  # Links the local password credential to its `user_identities` row.
  #
  # Password sign-in is validated by UserSignInForm (which owns the form errors
  # and the timing equalisation), so the password adapter's assertion is not what
  # authenticates it — but the identity row must exist all the same. Without it a
  # user whose password was written directly (login form, invitation signup,
  # admin panel, seeds) holds ZERO identities, and
  # `Auth::PolicyResolver.stranded_members` — which reads identities to decide
  # what a member can still use — reports them stranded under every prospective
  # policy, refusing even a purely additive edit.
  #
  # Writes still go through Auth::IdentityResolver, which remains the single
  # writer of user_identities (AD-3, AD-15). Auto-join is off: linking an
  # existing credential is not someone arriving for the first time.
  module LocalCredential
    module_function

    def link!(user)
      provider = IdentityProvider.password
      assertion = Auth::Assertion.new(
        provider: provider,
        subject: user.id.to_s,
        email: user.email,
        email_verified: true,
        name: user.name
      )
      Auth::IdentityResolver.new(assertion, auto_join: false).resolve
      provider
    end
  end
end
