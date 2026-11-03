# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # Contract test (R4) for the exchange of the assertion Flow signs for a token of
  # the customer's own Entra app. The login.microsoftonline.com surface is pinned
  # with WebMock. The payloads follow Microsoft's documentation; none of this has
  # been run against a live tenant.
  class FederatedTokenExchangeTest < ActiveSupport::TestCase
    setup do
      with_azure_devops_federation_only
      @company = create(:company)
      @tenant = SecureRandom.uuid
      @client_id = SecureRandom.uuid
    end

    def exchange(**overrides)
      FederatedTokenExchange.call(tenant_id: @tenant, client_id: @client_id, company: @company, **overrides)
    end

    def stub_exchange(status: 200, body: nil)
      captured = {}
      stub_request(:post, "#{AzureDevopsTestHelper::AZURE_TOKEN_HOST}/#{@tenant}/oauth2/v2.0/token").to_return do |request|
        captured.merge!(Rack::Utils.parse_query(request.body))
        { status: status, headers: { "Content-Type" => "application/json" },
          body: (body || { access_token: "customer-app-token", token_type: "Bearer", expires_in: 3599 }).to_json }
      end
      captured
    end

    test "sends the customer's client id with the assertion as a client-credentials request" do
      sent = stub_exchange

      payload = exchange

      assert_equal "customer-app-token", payload["access_token"]
      assert_equal "client_credentials", sent["grant_type"]
      assert_equal @client_id, sent["client_id"]
      assert_equal "https://app.vssps.visualstudio.com/.default", sent["scope"]
      assert_equal "urn:ietf:params:oauth:client-assertion-type:jwt-bearer", sent["client_assertion_type"]
    end

    test "the assertion names this company and nobody else" do
      sent = stub_exchange
      exchange
      other = create(:company)
      other_sent = stub_exchange
      exchange(company: other)

      claims = JWT.decode(sent["client_assertion"], nil, false).first
      other_claims = JWT.decode(other_sent["client_assertion"], nil, false).first

      assert_equal "aixle:company:#{@company.public_id}", claims["sub"]
      assert_equal "aixle:company:#{other.public_id}", other_claims["sub"]
      assert_equal "api://AzureADTokenExchange", claims["aud"]
      assert_equal AzureDevopsTestHelper::FEDERATION_ISSUER, claims["iss"]
    end

    test "names the likely cause when no federated credential matches the subject" do
      stub_exchange(status: 401, body: {
        error: "invalid_client",
        error_description: "AADSTS700213: No matching federated identity record found for presented assertion " \
                           "subject 'aixle:company:x'. Check your federated identity credential Subject, Audience " \
                           "and Issuer against the presented assertion.\r\nTrace ID: 0000\r\nTimestamp: now"
      })

      error = assert_raises(FederationRejected) { exchange }

      assert_match(/AADSTS700213/, error.message)
      assert_match(/case-sensitive/, error.message)
      assert_no_match(/Trace ID/, error.message)
    end

    test "an app that is not in the directory points at the client id" do
      stub_exchange(status: 400, body: { error: "unauthorized_client",
                                         error_description: "AADSTS700016: Application with identifier was not found." })

      error = assert_raises(FederationRejected) { exchange }

      assert_match(/client ID/, error.message)
    end

    test "an unrecognised rejection gets Entra's own code and the checklist, not a guess" do
      stub_exchange(status: 401, body: { error: "invalid_client", error_description: "AADSTS7000999: Something new." })

      error = assert_raises(FederationRejected) { exchange }

      assert_match(/AADSTS7000999/, error.message)
      assert_match(/issuer, subject and audience/, error.message)
    end

    test "another refusal is not blamed on the customer's credential" do
      stub_exchange(status: 400, body: { error: "invalid_scope", error_description: "AADSTS70011: bad scope" })

      assert_raises(NotAuthorized) { exchange }
    end

    test "a transport failure is reported as such" do
      stub_request(:post, "#{AzureDevopsTestHelper::AZURE_TOKEN_HOST}/#{@tenant}/oauth2/v2.0/token").to_timeout

      error = assert_raises(Error) { exchange }

      assert_equal "token_endpoint_unreachable", error.code
    end

    test "refuses a tenant or client id that is not a GUID before any request" do
      assert_raises(NotAuthorized) { exchange(tenant_id: "../evil") }
      assert_raises(ValidationFailed) { exchange(client_id: "not-a-guid") }
      assert_not_requested :post, /login.microsoftonline.com/
    end

    test "is an operator problem when this deployment cannot act as an issuer" do
      with_azure_devops_enabled

      assert_raises(CredentialActionRequired) { exchange }
    end
  end
end
