# frozen_string_literal: true

require "test_helper"

class OidcIssuerTest < ActionDispatch::IntegrationTest
  test "serves the discovery document and the keys to anyone, signed in or not" do
    with_azure_devops_federation_only

    get "/.well-known/openid-configuration"
    assert_response :success
    assert_equal "https://flow.example.com", response.parsed_body["issuer"]

    get "/.well-known/jwks.json"
    assert_response :success
    assert_equal [ AzureDevops::FederationConfig.current_key_id ], response.parsed_body["keys"].pluck("kid")
    assert_match(/public/, response.headers["Cache-Control"])
  end

  test "a token Flow signs verifies against what it publishes" do
    with_azure_devops_federation_only
    company = create(:company)
    tenant = SecureRandom.uuid
    assertion = nil
    stub_request(:post, "#{AzureDevopsTestHelper::AZURE_TOKEN_HOST}/#{tenant}/oauth2/v2.0/token").to_return do |request|
      assertion = Rack::Utils.parse_query(request.body)["client_assertion"]
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { access_token: "t", expires_in: 3600 }.to_json }
    end
    AzureDevops::FederatedTokenExchange.call(tenant_id: tenant, client_id: SecureRandom.uuid, company: company)

    get "/.well-known/jwks.json"
    jwks = JWT::JWK::Set.new(response.parsed_body)
    claims, = JWT.decode(assertion, nil, true, algorithms: [ "RS256" ], jwks: jwks, verify_aud: false)

    assert_equal AzureDevops::FederatedSubject.for(company), claims["sub"]
    assert_equal "https://flow.example.com", claims["iss"]
  end

  test "is not found when federation is not configured" do
    with_azure_devops_enabled

    get "/.well-known/openid-configuration"
    assert_response :not_found

    get "/.well-known/jwks.json"
    assert_response :not_found
  end
end
