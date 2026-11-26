# frozen_string_literal: true

module AwsOidc
  # Mints the short-lived JWT Flow hands to STS (docs/design/aws-oidc-integration.md §5.2).
  # Rails spends it in the same request, so it only has to outlive one STS call.
  module Token
    LIFETIME = 5.minutes
    AUDIENCE = "sts.amazonaws.com"
    TAGS_CLAIM = "https://aws.amazon.com/tags"

    Minted = Data.define(:token, :jti, :subject, :expires_at)

    module_function

    def mint(issuer:, subject:, tags: {})
      key = SigningKeys.current!
      now = Time.current
      jti = SecureRandom.uuid
      payload = { iss: issuer, aud: AUDIENCE, sub: subject, iat: now.to_i, nbf: now.to_i,
                  exp: (now + LIFETIME).to_i, jti: jti }
      payload[TAGS_CLAIM] = tags_claim(tags) if tags.any?

      token = JWT.encode(payload, key.private_key, "RS256", { kid: key.kid, typ: "JWT" })
      Minted.new(token: token, jti: jti, subject: subject, expires_at: now + LIFETIME)
    end

    def tags_claim(tags)
      { principal_tags: tags.to_h { |key, value| [ key.to_s, [ value.to_s ] ] }, transitive_tag_keys: [] }
    end
  end
end
