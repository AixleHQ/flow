# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # Contract test (R4) for the Entra client-credentials exchange: the real
  # login.microsoftonline.com surface is pinned with WebMock and realistic
  # payloads, and the installation row is real. There is no vendor SDK here to
  # stub, so nothing enters the NoVendorStubbing allowlist.
  class AppTokenServiceTest < ActiveSupport::TestCase
    setup do
      with_azure_devops_enabled
      @company = create(:company)
      @installation = create(:azure_devops_installation, :active, :approved, company: @company)
    end

    test "exchanges the app credential for an access token and caches it" do
      stub = stub_azure_token(tenant_id: @installation.tenant_id, token: "first-token")

      token = AppTokenService.new(@installation).access_token

      assert_equal "first-token", token.value
      assert_requested stub, times: 1

      @installation.reload
      assert_equal "first-token", @installation.cached_access_token
      assert_operator @installation.token_expires_at, :>, Time.current
      # Generation and resource travel with the entry: a rotation or a scope
      # change has to invalidate it without a sweep.
      assert_equal "v1", @installation.token_credential_generation
      assert_equal "https://app.vssps.visualstudio.com/.default", @installation.token_resource
    end

    test "serves a live cached token without calling Entra again" do
      stub = stub_azure_token(tenant_id: @installation.tenant_id)

      AppTokenService.new(@installation).access_token
      second = AppTokenService.new(@installation).access_token

      assert_equal "azure-access-token", second.value
      assert_requested stub, times: 1
    end

    test "reacquires when the cached token is inside the refresh skew" do
      stub_azure_token(tenant_id: @installation.tenant_id, token: "old", expires_in: 3600)
      AppTokenService.new(@installation).access_token

      # The skew is 300s, so a token 299s from expiry is already spent — this is
      # the case an "expires_at > now" check gets wrong.
      travel_to(@installation.reload.token_expires_at - 299.seconds) do
        stub_azure_token(tenant_id: @installation.tenant_id, token: "fresh")
        assert_equal "fresh", AppTokenService.new(@installation).access_token.value
      end
    end

    test "a rotated credential generation invalidates the cached token" do
      stub_azure_token(tenant_id: @installation.tenant_id, token: "generation-one")
      AppTokenService.new(@installation).access_token

      with_azure_devops_enabled(credential_generation: "v2")
      stub_azure_token(tenant_id: @installation.tenant_id, token: "generation-two")

      assert_equal "generation-two", AppTokenService.new(@installation).access_token.value
      assert_equal "v2", @installation.reload.token_credential_generation
    end

    test "a rejected client credential asks the operator to act rather than the user to sign in" do
      stub_azure_token(
        tenant_id: @installation.tenant_id, status: 401,
        body: { error: "invalid_client", error_description: "AADSTS7000215: Invalid client secret provided." }
      )

      error = assert_raises(CredentialActionRequired) { AppTokenService.new(@installation).access_token }
      assert_match(/invalid_client/, error.message)
      assert_equal "credential_action_required", error.code
    end

    test "a tenant that has not provisioned the application is an authorization failure, not a credential one" do
      stub_azure_token(
        tenant_id: @installation.tenant_id, status: 400,
        body: { error: "unauthorized_client", error_description: "The client does not exist in this tenant." }
      )

      # unauthorized_client is still the application's own problem to fix, so it
      # stays credential_action_required; the tenant-side gap surfaces as an
      # Azure DevOps 403 later, not here.
      assert_raises(CredentialActionRequired) { AppTokenService.new(@installation).access_token }
    end

    test "refresh_after_unauthorized discards the cached token and acquires a new one" do
      stub_azure_token(tenant_id: @installation.tenant_id, token: "stale")
      service = AppTokenService.new(@installation)
      service.access_token

      stub_azure_token(tenant_id: @installation.tenant_id, token: "reissued")
      assert_equal "reissued", service.refresh_after_unauthorized!.value
      # The cache entry is gone, not merely bypassed: a later reader must not
      # find the token Azure just refused.
      assert_equal "reissued", @installation.reload.cached_access_token
    end

    test "a token endpoint timeout is reported as a transport failure, not a bad credential" do
      stub_request(:post, "#{AZURE_TOKEN_HOST}/#{@installation.tenant_id}/oauth2/v2.0/token").to_timeout

      error = assert_raises(Error) { AppTokenService.new(@installation).access_token }
      assert_equal "token_endpoint_unreachable", error.code
    end

    test "refuses a tenant id that is not a GUID" do
      @installation.update_column(:tenant_id, "common")

      error = assert_raises(NotAuthorized) { AppTokenService.new(@installation).access_token }
      assert_match(/GUID/, error.message)
    end
  end
end
