# frozen_string_literal: true

require "test_helper"

module AwsOidc
  class TokenTest < ActiveSupport::TestCase
    ISSUER = "https://flow.example.com/oidc/abc"

    test "the token verifies against the published JWKS and carries the claims STS checks" do
      freeze_time do
        minted = Token.mint(issuer: ISSUER, subject: "workflow:12:step:34")
        payload, header = decode(minted.token)

        assert_equal ISSUER, payload["iss"]
        assert_equal "sts.amazonaws.com", payload["aud"]
        assert_equal "workflow:12:step:34", payload["sub"]
        assert_equal Time.current.to_i + Token::LIFETIME.to_i, payload["exp"]
        assert_equal minted.jti, payload["jti"]
        assert_equal OidcSigningKey.in_state("current").first.kid, header["kid"]
      end
    end

    test "session tags travel in the AWS tags claim as single-valued string lists" do
      minted = Token.mint(issuer: ISSUER, subject: "s", tags: { flow_project: 7, flow_user: 3 })
      payload, = decode(minted.token)

      assert_equal({ "principal_tags" => { "flow_project" => [ "7" ], "flow_user" => [ "3" ] },
                     "transitive_tag_keys" => [] }, payload[Token::TAGS_CLAIM])
    end

    test "no tags claim when there are no tags" do
      payload, = decode(Token.mint(issuer: ISSUER, subject: "s").token)

      assert_not payload.key?(Token::TAGS_CLAIM)
    end

    private

    def decode(token)
      jwks = JWT::JWK::Set.new(JSON.parse(SigningKeys.jwks.to_json))
      JWT.decode(token, nil, true, algorithms: [ "RS256" ], jwks: jwks, aud: "sts.amazonaws.com",
                                   verify_aud: true, iss: ISSUER, verify_iss: true)
    end
  end
end
