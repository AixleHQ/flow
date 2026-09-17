# frozen_string_literal: true

module Auth
  # Signed, short-lived, single-use `state` for a login redirect.
  #
  # Modelled on Oauth::State (the integrations broker) rather than reusing it:
  # that module's payload is about connecting a third-party account for an
  # already-authenticated user, and its credential store deliberately refuses to
  # persist an `id_token` — which is the one artifact a login flow needs. Same
  # proven shape, different purpose, separate signing purpose so a state minted
  # for one can never be replayed into the other.
  #
  # The signed payload carries only non-secret routing data. The PKCE
  # `code_verifier` and the OIDC `nonce` are NEVER in the URL — they live
  # server-side in a cache entry keyed by the state nonce, handed back exactly
  # once by #consume. A replayed link finds no entry and is refused.
  module State
    TTL = 10.minutes
    PURPOSE = :auth_login
    VERIFIER = -> { Rails.application.message_verifier("auth_login") }

    module_function

    def encode(identity_provider_id:, return_to:, code_verifier:, oidc_nonce:)
      state_nonce = SecureRandom.uuid
      Rails.cache.write(
        cache_key(state_nonce),
        { "code_verifier" => code_verifier, "oidc_nonce" => oidc_nonce },
        expires_in: TTL
      )
      VERIFIER.call.generate(
        {
          "identity_provider_id" => identity_provider_id,
          "return_to" => return_to,
          "nonce" => state_nonce
        },
        expires_in: TTL,
        purpose: PURPOSE
      )
    end

    # Signature + TTL only. Does not mutate the cache, so the error branch can
    # decode without burning the nonce.
    def decode(state)
      VERIFIER.call.verify(state.to_s, purpose: PURPOSE)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    # Single use: read + delete. nil means already used or expired, and the
    # caller MUST refuse to exchange the code.
    def consume(nonce)
      return nil if nonce.blank?

      key = cache_key(nonce)
      data = Rails.cache.read(key)
      return nil if data.nil?

      Rails.cache.delete(key)
      data
    end

    def cache_key(nonce)
      "auth_login_state:#{nonce}"
    end
  end
end
