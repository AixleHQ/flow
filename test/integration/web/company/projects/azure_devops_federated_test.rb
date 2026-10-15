# frozen_string_literal: true

require "test_helper"

# Connecting Azure DevOps through the customer's own Entra app, through the real
# endpoints. The Entra and Azure surfaces are WebMock stubs following Microsoft's
# documentation (R4); none of it has run against a live tenant.
class Web::Company::Projects::AzureDevopsFederatedTest < ActionDispatch::IntegrationTest
  setup do
    with_azure_devops_enabled(federation: federation_settings)
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    @tenant = SecureRandom.uuid
    @client_id = SecureRandom.uuid
    @azure_project_id = SecureRandom.uuid
    sign_in_as(@user)
  end

  def stub_azure
    stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/git/repositories})
      .to_return(status: 302, headers: { "WWW-Authenticate" => "Bearer authorization_uri=#{AZURE_TOKEN_HOST}/#{@tenant}" })
    stub_azure_token(tenant_id: @tenant, token: "h.#{Base64.urlsafe_encode64({ oid: SecureRandom.uuid }.to_json, padding: false)}.s")
    stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/projects\?.*\$top})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { value: [ { id: @azure_project_id, name: "Customer Platform" } ] }.to_json)
    json = { "Content-Type" => "application/json" }
    actions = %w[GenericRead GenericContribute CreateBranch PullRequestContribute WORK_ITEM_READ WORK_ITEM_WRITE
                 ViewBuilds ViewSubscriptions EditSubscriptions].each_with_index.map { |name, i| { name: name, bit: 2**i } }
    stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/securitynamespaces/.+})
      .to_return(status: 200, headers: json, body: { value: [ { actions: actions } ] }.to_json)
    stub_request(:get, %r{#{AZURE_API_HOST}/contoso/[^/]+/_apis/wit/classificationnodes/areas})
      .to_return(status: 200, headers: json, body: { identifier: SecureRandom.uuid }.to_json)
    stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/permissions/})
      .to_return(status: 200, headers: json, body: { value: [ true ] }.to_json)
  end

  test "the page offers the customer's own app with this company's subject" do
    get company_project_integrations_path(@project)

    assert_inertia_props do |props|
      federation = props["azureDevops"]["federation"]
      assert_equal AzureDevopsTestHelper::FEDERATION_ISSUER, federation["issuerUrl"]
      assert_equal "api://AzureADTokenExchange", federation["audience"]
      assert_equal "aixle:company:#{@company.public_id}", federation["subject"]
    end
  end

  test "the page does not offer it where this deployment cannot be an issuer" do
    with_azure_devops_enabled

    get company_project_integrations_path(@project)

    assert_inertia_props { |props| assert_not props["azureDevops"].key?("federation") }
  end

  test "a deployment with no shared app can still connect through the customer's own" do
    with_azure_devops_federation_only

    get company_project_integrations_path(@project)

    assert_inertia_props do |props|
      azure = props["azureDevops"]
      assert azure["enabled"]
      assert_equal false, azure["sharedAppEnabled"] # rubocop:disable Minitest/RefuteFalse
      assert_nil azure["clientId"]
      assert azure["federation"].present?
    end
  end

  test "inspect lists what the app can see" do
    stub_azure

    post azure_devops_federated_inspect_company_project_integrations_path(@project),
         params: { organization: "contoso", client_id: @client_id }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal @tenant, body["tenantId"]
    assert_equal [ "Customer Platform" ], body["projects"].pluck("name")
    assert_nil body["permissions"]
  end

  test "inspect reports permissions for the projects it is asked about" do
    stub_azure

    post azure_devops_federated_inspect_company_project_integrations_path(@project),
         params: { organization: "contoso", client_id: @client_id, project_ids: [ @azure_project_id ] }, as: :json

    assert_response :success
    assert_equal true, response.parsed_body.dig("permissions", "ok") # rubocop:disable Minitest/AssertTruthy
  end

  test "inspect explains a credential Entra does not match" do
    stub_azure
    stub_azure_token(tenant_id: @tenant, status: 401,
                     body: { error: "invalid_client", error_description: "AADSTS700213: No matching federated identity record." })

    post azure_devops_federated_inspect_company_project_integrations_path(@project),
         params: { organization: "contoso", client_id: @client_id }, as: :json

    assert_response :unprocessable_content
    assert_equal "federation_rejected", response.parsed_body["error"]
    assert_match(/subject/, response.parsed_body["message"])
  end

  test "connect records the binding the connection is then made on" do
    stub_azure

    post azure_devops_federated_connect_company_project_integrations_path(@project),
         params: { organization: "contoso", client_id: @client_id, project_ids: [ @azure_project_id ] }, as: :json

    assert_response :success
    installation = AzureDevopsInstallation.find(response.parsed_body["installationId"])
    assert_predicate installation, :federated?
    assert_equal @company.id, installation.company_id
    assert_equal [ @azure_project_id ], installation.allowed_project_ids

    stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/projects/#{@azure_project_id}})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id: @azure_project_id, name: "Customer Platform" }.to_json)
    post company_project_integrations_path(@project), params: {
      provider: "azure_devops", azure_devops_installation_id: installation.id, azure_project_ids: [ @azure_project_id ]
    }

    integration = @company.integrations.find_by!(provider: "azure_devops")
    assert_predicate integration, :active?
    assert_equal installation.id, integration.azure_devops_installation_id
    assert_equal "Your Entra app (#{@client_id.first(8)}…)", integration.settings["identity_display_name"]
  end

  test "connect without any project is refused" do
    stub_azure

    post azure_devops_federated_connect_company_project_integrations_path(@project),
         params: { organization: "contoso", client_id: @client_id, project_ids: [] }, as: :json

    assert_response :unprocessable_content
    assert_equal 0, AzureDevopsInstallation.count
  end

  test "the script is generated for the organization's tenant and the given app" do
    stub_azure

    post azure_devops_federated_script_company_project_integrations_path(@project),
         params: { organization: "contoso", client_id: @client_id, flavor: "custom", service_hooks: "false" }, as: :json

    assert_response :success
    script = response.parsed_body["script"]
    assert_includes script, "TENANT_ID='#{@tenant}'"
    assert_includes script, "CLIENT_ID='#{@client_id}'"
    assert_includes script, "SERVICE_HOOKS=0"
    assert_includes script, "repoV2"
  end

  test "a client id that is not a GUID gets no script" do
    stub_azure

    post azure_devops_federated_script_company_project_integrations_path(@project),
         params: { organization: "contoso", client_id: "$(rm -rf /)" }, as: :json

    assert_response :unprocessable_content
  end
end
