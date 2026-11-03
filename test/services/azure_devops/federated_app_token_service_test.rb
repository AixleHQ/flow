# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # AppTokenService for an installation that runs on the customer's own Entra app.
  # The shared-app behaviour is covered in AppTokenServiceTest.
  class FederatedAppTokenServiceTest < ActiveSupport::TestCase
    setup do
      with_azure_devops_federation_only
      @company = create(:company)
      @installation = create(:azure_devops_installation, :federated, :active, :approved, company: @company)
    end

    test "needs no operator app configuration" do
      stub = stub_azure_token(tenant_id: @installation.tenant_id, token: "customer-token")

      token = AppTokenService.new(@installation).access_token

      assert_equal "customer-token", token.value
      assert_requested stub, times: 1
      assert_equal "federated:#{@installation.client_id}", @installation.reload.token_credential_generation
    end

    test "serves a live cached token without exchanging again" do
      stub = stub_azure_token(tenant_id: @installation.tenant_id)

      AppTokenService.new(@installation).access_token
      AppTokenService.new(@installation).access_token

      assert_requested stub, times: 1
    end

    test "a token cached for the old app is not served after the client id changes" do
      stub_azure_token(tenant_id: @installation.tenant_id, token: "old-app")
      AppTokenService.new(@installation).access_token

      @installation.update!(client_id: SecureRandom.uuid, service_principal_object_id: nil)
      stub_azure_token(tenant_id: @installation.tenant_id, token: "new-app")

      assert_equal "new-app", AppTokenService.new(@installation).access_token.value
    end

    test "a deleted federated credential surfaces as a customer-side rejection" do
      stub_azure_token(
        tenant_id: @installation.tenant_id, status: 401,
        body: { error: "invalid_client",
                error_description: "AADSTS700213: No matching federated identity record found for presented assertion subject 'x'." }
      )

      error = assert_raises(FederationRejected) { AppTokenService.new(@installation).access_token }

      assert_equal "federation_rejected", error.code
    end

    test "without a signing key it is the operator's problem" do
      with_azure_devops_enabled

      assert_raises(CredentialActionRequired) { AppTokenService.new(@installation).access_token }
    end
  end
end
