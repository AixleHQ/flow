# frozen_string_literal: true

module Auth
  # Records which authentication methods a login session has satisfied (AD-6).
  #
  # The session itself is a UserSession: starting, revoking and timing one out
  # belong to that model. This adds the one thing the company-entry gate needs
  # that a session row alone cannot answer — HOW the person authenticated.
  module SessionService
    module_function

    # Proofs append: proving a second method never invalidates the first.
    def record_proof(user_session, provider)
      return nil if user_session.nil? || provider.nil?

      proof = UserSessionProof.find_or_initialize_by(
        user_session: user_session, identity_provider: provider
      )
      proof.proved_at = Time.current
      proof.save!
      proof
    end
  end
end
