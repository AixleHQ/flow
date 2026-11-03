# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # Re-testing a connection that runs on the customer's own Entra app: permissions
  # an administrator removed later show up on the connection as a warning, instead
  # of as a failed tool call. WebMock stubs follow Microsoft's documentation and
  # have not run against a live tenant.
  class FederatedIntegrationServiceTest < ActiveSupport::TestCase
    setup do
      with_azure_devops_enabled(federation: federation_settings)
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project_id = SecureRandom.uuid
      @installation = create(:azure_devops_installation, :federated, :active, :approved, company: @company,
                                                                                         organization_slug: "contoso",
                                                                                         allowed_project_ids: [ @project_id ])
      @integration = create(:integration, :azure_devops, :active, company: @company, azure_project_id: @project_id,
                                                                  azure_devops_installation: @installation)
      @service = IntegrationService.new(company: @company, connected_by: @user, project: @integration.project)

      stub_azure_token(tenant_id: @installation.tenant_id)
      stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/projects/#{@project_id}})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { id: @project_id, name: "Customer Platform" }.to_json)
      json = { "Content-Type" => "application/json" }
      actions = %w[GenericRead GenericContribute CreateBranch PullRequestContribute WORK_ITEM_READ WORK_ITEM_WRITE
                   ViewBuilds ViewSubscriptions EditSubscriptions].each_with_index.map { |name, i| { name: name, bit: 2**i } }
      stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/securitynamespaces/.+})
        .to_return(status: 200, headers: json, body: { value: [ { actions: actions } ] }.to_json)
      stub_request(:get, %r{#{AZURE_API_HOST}/contoso/[^/]+/_apis/wit/classificationnodes/areas})
        .to_return(status: 200, headers: json, body: { identifier: SecureRandom.uuid }.to_json)
    end

    def stub_permissions(granted)
      stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/permissions/})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { value: [ granted ] }.to_json)
    end

    test "a connection whose permissions are all there tests clean" do
      stub_permissions(true)

      result = @service.test(@integration)

      assert_equal :active, result[:status]
      assert_not result[:warning]
      assert result[:permissions][:ok]
    end

    test "permissions removed later are a warning that names them, not a failure" do
      stub_permissions(false)

      result = @service.test(@integration)

      assert_equal :active, result[:status]
      assert result[:warning]
      assert_match(/Missing permissions: .*Repos → Read/, result[:message])
      assert_predicate @integration.reload, :active?
    end

    test "the connection shows it runs on the customer's own app" do
      stub_permissions(true)

      @service.test(@integration)

      assert_match(/\AYour Entra app \(#{@installation.client_id.first(8)}/, @integration.reload.settings["identity_display_name"])
    end

    test "a shared-app connection is not permission-checked" do
      shared = create(:integration, :azure_devops, :active, company: @company)
      stub_azure_token(tenant_id: shared.azure_devops_installation.tenant_id)
      stub_request(:get, %r{#{AZURE_API_HOST}/#{shared.azure_devops_installation.organization_slug}/_apis/projects/})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { id: shared.azure_project_ids.first, name: "Customer Platform" }.to_json)

      result = IntegrationService.new(company: @company, connected_by: @user, project: shared.project).test(shared)

      assert_nil result[:permissions]
    end
  end
end
