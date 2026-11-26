# frozen_string_literal: true

module AwsOidc
  # The instance's signing key set (docs/design/aws-oidc-integration.md §5.4).
  #
  # Rotation happens on use rather than on a schedule: a key only matters while
  # tokens are being signed with it, so the signer rotates when it finds the current
  # key old enough. `next` is published in the JWKS from the moment it is created and
  # signs nothing until PUBLISH_LEAD has passed, because STS caches a provider's JWKS
  # and must already hold the key when the first token signed with it arrives.
  module SigningKeys
    ROTATE_AFTER = 30.days
    PUBLISH_LEAD = 1.day
    # Longer than a token lives (AwsOidc::Token::LIFETIME) plus STS's JWKS cache, so
    # a token signed just before a rotation still verifies.
    RETIRED_GRACE = 1.hour
    LOCK_KEY = "aws_oidc:signing_keys"

    module_function

    def current!
      key = OidcSigningKey.in_state("current").first
      return key if key && !rotation_due?(key)

      with_lock do
        bootstrap! if OidcSigningKey.in_state("current").none?
        rotate_if_due!
        OidcSigningKey.in_state("current").first!
      end
    end

    def jwks
      { keys: published.order(:created_at).map(&:public_jwk) }
    end

    def published
      OidcSigningKey.where(state: %w[next current])
                    .or(OidcSigningKey.where(state: "retired").where(retired_at: RETIRED_GRACE.ago..))
    end

    def generate!(state)
      rsa = OpenSSL::PKey::RSA.new(2048)
      kid = SecureRandom.urlsafe_base64(12)
      jwk = JWT::JWK.new(rsa.public_key, kid: kid).export.merge(use: "sig", alg: "RS256")
      OidcSigningKey.create!(kid: kid, state: state, public_jwk: jwk, private_key: rsa.to_pem,
                             activated_at: (Time.current if state == "current"))
    end

    def rotation_due?(key)
      return false if key.activated_at > ROTATE_AFTER.ago

      OidcSigningKey.in_state("next").where(created_at: ..PUBLISH_LEAD.ago).exists?
    end

    def bootstrap!
      generate!("current")
      generate!("next") if OidcSigningKey.in_state("next").none?
    end

    def rotate_if_due!
      current = OidcSigningKey.in_state("current").first!
      return unless rotation_due?(current)

      successor = OidcSigningKey.in_state("next").order(:created_at).first!
      now = Time.current
      current.update!(state: "retired", retired_at: now)
      successor.update!(state: "current", activated_at: now)
      generate!("next")
      OidcSigningKey.where(state: "retired", retired_at: ...RETIRED_GRACE.ago).delete_all
    end

    def with_lock(&)
      OidcSigningKey.transaction do
        OidcSigningKey.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))", LOCK_KEY ])
        )
        yield
      end
    end
  end
end
