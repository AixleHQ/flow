# frozen_string_literal: true

module Auth
  module Methods
    # Passkeys (WebAuthn). The gem owns the ceremonies and attestation
    # verification; this app owns storage, the UI and recovery.
    #
    # Discoverable credentials are the point: the browser hands back which
    # credential was used, so a passkey sign-in needs no username first.
    class Passkey < Auth::Method
      def complete(credential:, challenge:)
        webauthn_credential = WebAuthn::Credential.from_get(credential)
        stored = WebauthnCredential.find_by(external_id: webauthn_credential.id)
        raise Auth::Method::Failure, "unknown passkey" if stored.nil?

        webauthn_credential.verify(
          challenge,
          public_key: stored.public_key,
          sign_count: stored.sign_count
        )
        # A sign count that goes backwards is the documented signal of a cloned
        # authenticator; the gem raises on it, and we record the new one.
        stored.touch_used!(webauthn_credential.sign_count)

        user = stored.user
        Auth::Assertion.new(
          provider: provider,
          subject: user.id.to_s,
          email: user.email,
          email_verified: true,
          name: user.name
        )
      rescue WebAuthn::Error => e
        raise Auth::Method::Failure, "passkey verification failed: #{e.class}"
      end
    end
  end
end
