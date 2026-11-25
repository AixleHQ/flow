# frozen_string_literal: true

require "test_helper"

# STS fetches these two documents without credentials; anything but a connected
# integration with the flag on must look like nothing is there.
class AwsOidc::IssuerTest < ActionDispatch::IntegrationTest
  setup do
    @integration = create(:integration, :aws_oidc)
    @key = @integration.aws_oidc_issuer_key
  end

  test "the discovery document names this integration's issuer and its JWKS" do
    with_feature(:aws_oidc, true) do
      get "/oidc/#{@key}/.well-known/openid-configuration"

      assert_response :ok
      doc = JSON.parse(response.body)
      assert_equal AwsOidc::Issuer.url(@integration), doc["issuer"]
      assert_equal "#{doc['issuer']}/jwks", doc["jwks_uri"]
      assert_equal [ "RS256" ], doc["id_token_signing_alg_values_supported"]
      assert_match(/public/, response.headers["Cache-Control"])
    end
  end

  test "the JWKS lists the instance's published keys" do
    with_feature(:aws_oidc, true) do
      get "/oidc/#{@key}/jwks"

      assert_response :ok
      assert_equal AwsOidc::SigningKeys.jwks[:keys].map { |jwk| jwk["kid"] },
                   JSON.parse(response.body)["keys"].map { |jwk| jwk["kid"] }
    end
  end

  test "an unknown key, a disconnected integration and a flag-off company all answer 404" do
    with_feature(:aws_oidc, true) do
      get "/oidc/nope/jwks"
      assert_response :not_found

      @integration.update!(status: "inactive")
      get "/oidc/#{@key}/.well-known/openid-configuration"
      assert_response :not_found
    end

    @integration.update!(status: "active")
    with_feature(:aws_oidc, false) do
      get "/oidc/#{@key}/jwks"
      assert_response :not_found
    end
  end
end
