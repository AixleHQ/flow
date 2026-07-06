# frozen_string_literal: true

module Oauth
  # Signed, short-lived, single-use OAuth `state`. Generalized from Slack::Oauth.
  #
  # The signed payload (which travels in the authorize/callback URL) carries only
  # non-secret routing data: which provider, which owner identity, which user
  # initiated the flow, an optional MCP server, a post-connect return path, and a
  # nonce. The PKCE `code_verifier` is NEVER put in the URL — it is kept
  # server-side in the cache entry keyed by the nonce and handed back exactly once
  # via #consume. `user_id` is stored on BOTH sides (signed AND cached) so the
  # callback can double-pin the initiating user (anti-CSRF, defense in depth).
  #
  # Single use is enforced by deleting the cache entry the first time #consume
  # reads it: a replayed link finds no entry and is rejected.
  module State
    TTL = 10.minutes
    PURPOSE = :oauth
    VERIFIER = -> { Rails.application.message_verifier("oauth") }

    module_function

    # Signs the routing payload and, as a side effect, caches the single-use
    # side-data ({code_verifier, user_id}) under the nonce for TTL. Returns the
    # signed state string that goes into the provider authorize URL.
    #
    # `provider` is part of the SIGNED payload: the deployment-wide callback reads
    # it back to know which authorization server issued the code. It cannot be
    # tampered with (signature) and never needs to be re-derived from params.
    def encode(owner_type:, owner_id:, user_id:, return_to:, code_verifier:, provider:, mcp_server_id: nil)
      nonce = SecureRandom.uuid
      Rails.cache.write(
        cache_key(nonce),
        { "code_verifier" => code_verifier, "user_id" => user_id },
        expires_in: TTL
      )
      VERIFIER.call.generate(
        {
          "owner_type" => owner_type,
          "owner_id" => owner_id,
          "user_id" => user_id,
          "provider" => provider,
          "mcp_server_id" => mcp_server_id,
          "return_to" => return_to,
          "nonce" => nonce
        },
        expires_in: TTL,
        purpose: PURPOSE
      )
    end

    # Verify signature + TTL only. Returns the decoded payload hash, or nil if the
    # state was tampered with or has expired. Does NOT mutate the cache, so it is
    # safe to call before the cancel/error branch (the nonce stays consumable).
    def decode(state)
      VERIFIER.call.verify(state.to_s, purpose: PURPOSE)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    # Single-use consume: read + delete the cached side-data for this nonce.
    # Returns { "code_verifier" => ..., "user_id" => ... } the FIRST time, and nil
    # on replay or after TTL expiry. Callers MUST treat nil as "already used or
    # expired" and refuse to exchange the code.
    def consume(nonce)
      return nil if nonce.blank?

      key = cache_key(nonce)
      data = Rails.cache.read(key)
      return nil if data.nil?

      Rails.cache.delete(key)
      data
    end

    def cache_key(nonce)
      "oauth_state:#{nonce}"
    end
  end
end
