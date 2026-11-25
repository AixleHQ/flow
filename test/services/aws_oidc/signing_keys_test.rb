# frozen_string_literal: true

require "test_helper"

module AwsOidc
  class SigningKeysTest < ActiveSupport::TestCase
    test "the first use creates a current key and a published next key" do
      current = SigningKeys.current!

      assert_equal "current", current.state
      assert_equal 1, OidcSigningKey.in_state("next").count
      assert_equal [ current.kid, OidcSigningKey.in_state("next").first.kid ].sort,
                   SigningKeys.jwks[:keys].map { |jwk| jwk["kid"] }.sort
    end

    test "the JWKS holds RSA public keys and nothing private" do
      SigningKeys.current!
      jwk = SigningKeys.jwks[:keys].first

      assert_equal "RSA", jwk["kty"]
      assert_equal "RS256", jwk["alg"]
      assert_equal "sig", jwk["use"]
      assert_empty jwk.keys & %w[d p q dp dq qi]
    end

    test "a current key keeps signing until it is old enough and the next key has been published long enough" do
      first = SigningKeys.current!

      travel_to(SigningKeys::ROTATE_AFTER.from_now - 1.hour) do
        assert_equal first.kid, SigningKeys.current!.kid
      end
    end

    test "rotation promotes next, publishes a new next and keeps the retired key for its grace period" do
      first = SigningKeys.current!
      successor = OidcSigningKey.in_state("next").first

      travel_to(SigningKeys::ROTATE_AFTER.from_now + 1.minute) do
        rotated = SigningKeys.current!

        assert_equal successor.kid, rotated.kid
        assert_equal "retired", first.reload.state
        assert_equal 1, OidcSigningKey.in_state("next").count
        assert_includes SigningKeys.jwks[:keys].map { |jwk| jwk["kid"] }, first.kid
      end

      travel_to(SigningKeys::ROTATE_AFTER.from_now + SigningKeys::RETIRED_GRACE + 2.minutes) do
        assert_not_includes SigningKeys.jwks[:keys].map { |jwk| jwk["kid"] }, first.kid
      end
    end

    test "a next key younger than the publish lead does not take over" do
      first = SigningKeys.current!
      OidcSigningKey.in_state("next").delete_all

      travel_to(SigningKeys::ROTATE_AFTER.from_now + 1.minute) do
        SigningKeys.generate!("next")

        assert_equal first.kid, SigningKeys.current!.kid
      end
    end

    test "the private key round-trips through encryption" do
      key = SigningKeys.current!

      assert key.private_key.private?
      assert_not_includes key.encrypted_private_key, "BEGIN"
    end
  end
end
