# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # The authorization chain, which is the whole point of this class: an app-only
  # token proves the APPLICATION can reach an organization and proves nothing
  # about who is asking. Every link is asserted separately because each one has
  # its own failure mode.
  class CredentialProviderTest < ActiveSupport::TestCase
    setup do
      with_azure_devops_enabled
      @integration = create(:integration, :azure_devops, :active)
      @installation = @integration.azure_devops_installation
      stub_azure_token(tenant_id: @installation.tenant_id)
    end

    test "resolves a service-principal connection into a bearer credential" do
      resolved = CredentialProvider.resolve!(@integration)

      assert_equal :service_principal, resolved.mode
      assert_equal @installation.organization_slug, resolved.organization
      assert_equal @integration.azure_project_id, resolved.project_id
      assert_equal "Bearer azure-access-token", resolved.authorization_headers["Authorization"]

      credential = resolved.git_credential
      assert_equal "bearer", credential[:scheme]
      assert credential[:expires_in].positive?
    end

    test "refuses every connection on a deployment nobody configured" do
      with_azure_devops_unconfigured

      error = assert_raises(IntegrationUnavailable) { CredentialProvider.resolve!(@integration) }
      assert_match(/not enabled/, error.message)
    end

    # The other half of deriving availability from configuration: a deployment
    # that only permits PAT mode still offers the feature, because that
    # credential arrives per connection rather than from operator settings.
    test "PAT mode alone makes the feature available without any app credential" do
      Settings.stubs(:azure_devops).returns(
        Hashie::Mash.new(pat_mode_enabled: true, api_host: AZURE_API_HOST,
                         apps: { "default" => { "client_id" => nil } })
      )
      pat_integration = create(:integration, :azure_devops_pat, :active)

      assert_equal :pat, CredentialProvider.resolve!(pat_integration).mode
    end

    test "refuses an inactive connection" do
      @integration.update!(status: :inactive)

      assert_raises(IntegrationUnavailable) { CredentialProvider.resolve!(@integration) }
    end

    test "refuses a capability the connection does not enable, before reaching Azure" do
      @integration.settings = @integration.settings.merge("enabled_capabilities" => [ "repositories.read" ])
      @integration.save!

      error = assert_raises(NotAuthorized) do
        CredentialProvider.resolve!(@integration, capability: :"work_items.write")
      end
      assert_match(/work_items.write/, error.message)
      # Nothing was asked of Entra: a disabled operation never becomes a request.
      assert_not_requested :post, "#{AZURE_TOKEN_HOST}/#{@installation.tenant_id}/oauth2/v2.0/token"
    end

    test "refuses when the installation belongs to another company" do
      # The binding is what says THIS company may reach that organization;
      # without the check an id from elsewhere would resolve happily.
      other = create(:azure_devops_installation, :active, :approved,
                     allowed_project_ids: [ @integration.azure_project_id ])
      @integration.update_column(:azure_devops_installation_id, other.id)

      error = assert_raises(NotAuthorized) { CredentialProvider.resolve!(@integration.reload) }
      assert_match(/another company/, error.message)
    end

    test "refuses when the installation has been disabled" do
      @installation.update!(status: :inactive)

      assert_raises(IntegrationUnavailable) { CredentialProvider.resolve!(@integration.reload) }
    end

    test "refuses when the selected Azure project has left the approved scope" do
      @installation.update!(allowed_project_ids: [ SecureRandom.uuid ])

      error = assert_raises(NotAuthorized) { CredentialProvider.resolve!(@integration.reload) }
      assert_match(/approved scope/, error.message)
    end

    test "PAT mode is refused unless the deployment enables it" do
      pat_integration = create(:integration, :azure_devops_pat, :active)

      error = assert_raises(IntegrationUnavailable) { CredentialProvider.resolve!(pat_integration) }
      assert_match(/PAT mode is not enabled/, error.message)
    end

    test "PAT mode resolves to basic authentication with no expiry" do
      with_azure_devops_enabled(pat_mode: true)
      pat_integration = create(:integration, :azure_devops_pat, :active)

      resolved = CredentialProvider.resolve!(pat_integration)

      assert_equal :pat, resolved.mode
      assert_match(/\ABasic /, resolved.authorization_headers["Authorization"])
      credential = resolved.git_credential
      assert_equal "basic", credential[:scheme]
      assert_nil credential[:expires_in]
    end

    test "refuses a non-Azure integration outright" do
      github = create(:integration, :github, :active)

      assert_raises(IntegrationUnavailable) { CredentialProvider.resolve!(github) }
    end
  end
end
