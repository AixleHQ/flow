# frozen_string_literal: true

module Auth
  # Creates, proves and revokes server-side login sessions (AD-6).
  #
  # The session token ROTATES on every successful authentication: `start` mints a
  # fresh row and the caller resets the cookie session, so a session fixed before
  # a step-up cannot inherit the proof that step-up produces.
  module SessionService
    module_function

    Started = Struct.new(:auth_session, :token, keyword_init: true)

    def start(user:, provider:, ip: nil, user_agent: nil)
      token = "#{AuthSession::TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"

      auth_session = AuthSession.create!(
        user: user,
        token_digest: AuthSession.digest(token),
        ip: ip,
        user_agent: user_agent,
        last_seen_at: Time.current
      )
      append_proof(auth_session, provider)

      Started.new(auth_session: auth_session, token: token)
    end

    # Proofs append: proving a second method never invalidates the first.
    def append_proof(auth_session, provider)
      proof = AuthSessionProof.find_or_initialize_by(
        auth_session: auth_session, identity_provider: provider
      )
      proof.proved_at = Time.current
      proof.save!
      proof
    end

    def revoke(auth_session)
      auth_session&.revoke!
    end

    def revoke_all_for(user)
      AuthSession.live.where(user: user).find_each(&:revoke!)
    end

    def touch(auth_session)
      return if auth_session.nil?
      return if auth_session.last_seen_at.present? && auth_session.last_seen_at > 1.minute.ago

      auth_session.update_column(:last_seen_at, Time.current)
    end
  end
end
