# frozen_string_literal: true

require "test_helper"

# The connect, edit and test flows through the real endpoints. The thread running
# through all of them: a project administrator cannot widen their own reach by
# submitting ids — the approved installation is what grants access, and it is
# established out of band.
# These drive the connect/verify/repair flow end to end through the real
# IntegrationService, CredentialProvider and Client — none of which FakeAzureDevops
# replaces — so the WebMock stubs here ARE this flow's contract (R4), not stray
# stubs in a feature test.
class Web::Company::Projects::AzureDevopsIntegrationsTest < ActionDispatch::IntegrationTest
  setup do
    # No webhook base URL, so activation does not try to provision Service Hooks:
    # that path has its own test in subscription_service_test.
    with_azure_devops_enabled
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    @azure_project_id = SecureRandom.uuid
    @installation = create(:azure_devops_installation, :active, :approved,
                           company: @company, allowed_project_ids: [ @azure_project_id ])
    sign_in_as(@user)
  end

  test "the page offers only this company's approved organizations, and calls Azure for none of them" do
    other_company_installation = create(:azure_devops_installation, :active, :approved)

    get company_project_integrations_path(@project)

    assert_inertia_page "Projects/Integrations/IntegrationsPage"
    assert_inertia_props do |props|
      azure = props["azureDevops"]
      assert azure["enabled"]
      ids = azure["installations"].map { |i| i["id"] }
      assert_includes ids, @installation.id
      refute_includes ids, other_company_installation.id
      # No project list yet — listing one is a live Azure call, and it does not
      # belong on the critical path of a page most visitors are not connecting
      # anything from.
      assert_nil azure["installations"].first["projects"]
    end
    assert_not_requested :post, "#{AZURE_TOKEN_HOST}/#{@installation.tenant_id}/oauth2/v2.0/token"
  end

  test "asking about one installation lists only the projects its approval covers" do
    stub_azure_token(tenant_id: @installation.tenant_id)
    stub_projects_list

    get company_project_integrations_path(@project, azure_devops_installation_id: @installation.id)

    assert_inertia_props do |props|
      installation = props["azureDevops"]["installations"].find { |i| i["id"] == @installation.id }
      # Azure returned two projects; only the approved one is offered.
      assert_equal [ @azure_project_id ], installation["projects"].map { |p| p["id"] }
    end
  end

  test "the connect entry is hidden entirely on a deployment nobody configured" do
    with_azure_devops_unconfigured

    get company_project_integrations_path(@project)

    assert_inertia_props { |props| assert_equal false, props["azureDevops"]["enabled"] } # rubocop:disable Minitest/RefuteFalse
  end

  test "connecting binds the approved installation to one verified Azure project" do
    stub_azure_token(tenant_id: @installation.tenant_id)
    stub_project_get

    assert_difference -> { Integration.where(provider: "azure_devops").count }, 1 do
      post company_project_integrations_path(@project), params: {
        provider: "azure_devops",
        azure_devops_installation_id: @installation.id,
        azure_project_id: @azure_project_id
      }
    end

    integration = Integration.where(provider: "azure_devops").last
    assert integration.active?
    assert_equal @project.id, integration.project_id
    assert_equal @installation.id, integration.azure_devops_installation_id
    assert_equal "Customer Platform", integration.azure_project_name
    # Nothing secret reaches the settings blob, which is serialized whole.
    refute_match(/secret|token|password/i, integration.settings.to_json)
  end

  test "an Azure project outside the approved scope is refused" do
    post company_project_integrations_path(@project), params: {
      provider: "azure_devops",
      azure_devops_installation_id: @installation.id,
      azure_project_id: SecureRandom.uuid
    }

    assert_redirected_to company_project_integrations_path(@project)
    assert_match(/approved scope/, flash[:alert])
    assert_equal 0, Integration.where(provider: "azure_devops").count
  end

  test "another company's installation is refused even with a valid id" do
    foreign = create(:azure_devops_installation, :active, :approved, allowed_project_ids: [ @azure_project_id ])

    post company_project_integrations_path(@project), params: {
      provider: "azure_devops",
      azure_devops_installation_id: foreign.id,
      azure_project_id: @azure_project_id
    }

    assert_match(/No approved Azure organization installation/, flash[:alert])
    assert_equal 0, Integration.where(provider: "azure_devops").count
  end

  # The fastest path to a working connection, and the one a pilot uses: no Entra
  # work at all, at the cost of acting as the token's owner.
  test "PAT mode connects against a verified project and stores the token encrypted" do
    with_azure_devops_enabled(pat_mode: true)
    stub_request(:get, %r{/_apis/projects/#{@azure_project_id}}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: @azure_project_id, name: "Customer Platform" }.to_json
    )

    post company_project_integrations_path(@project), params: {
      provider: "azure_devops", auth_mode: "pat",
      organization_slug: "contoso", azure_project_id: @azure_project_id,
      personal_access_token: "azdo-pilot-token"
    }

    integration = Integration.where(provider: "azure_devops").last
    assert integration.active?
    assert_equal "pat", integration.azure_auth_mode
    assert_nil integration.azure_devops_installation_id
    assert_equal "azdo-pilot-token", integration.azure_personal_access_token
    # The credentials column is encrypted and `settings` is serialized whole to
    # the browser, so neither may carry the token in the clear.
    refute_includes integration.credentials.to_s, "azdo-pilot-token"
    refute_includes integration.settings.to_json, "azdo-pilot-token"
  end

  # Azure authenticates a PAT as Basic with an empty username; an Entra token is
  # Bearer. The two are not interchangeable, so assert the wire shape.
  test "PAT mode authenticates with basic auth rather than a bearer token" do
    with_azure_devops_enabled(pat_mode: true)
    expected = "Basic #{Base64.strict_encode64(':azdo-pilot-token')}"
    stub_request(:get, %r{/_apis/projects/#{@azure_project_id}})
      .with(headers: { "Authorization" => expected })
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id: @azure_project_id, name: "Customer Platform" }.to_json)

    post company_project_integrations_path(@project), params: {
      provider: "azure_devops", auth_mode: "pat",
      organization_slug: "contoso", azure_project_id: @azure_project_id,
      personal_access_token: "azdo-pilot-token"
    }

    # The stub only matches the Basic header, so an active connection is itself
    # the assertion that nothing sent a bearer token.
    assert Integration.where(provider: "azure_devops").last.active?
    # No Entra exchange happens in this mode at all.
    assert_not_requested :post, %r{login\.microsoftonline\.com}
  end

  test "PAT mode is refused while the deployment has it switched off" do
    post company_project_integrations_path(@project), params: {
      provider: "azure_devops", auth_mode: "pat",
      organization_slug: "contoso", azure_project_id: @azure_project_id,
      personal_access_token: "azdo-secret"
    }

    assert_match(/PAT mode is not enabled/, flash[:alert])
  end

  test "a connection whose selected project is unreachable is recorded as an error, not as connected" do
    stub_azure_token(tenant_id: @installation.tenant_id)
    stub_request(:get, %r{/_apis/projects/#{@azure_project_id}}).to_return(status: 403, body: "")

    post company_project_integrations_path(@project), params: {
      provider: "azure_devops",
      azure_devops_installation_id: @installation.id,
      azure_project_id: @azure_project_id
    }

    integration = Integration.where(provider: "azure_devops").last
    assert integration.error?
    assert_match(/permission_denied/, integration.settings["error"])
  end

  test "update no longer runs Coder's settings logic against another provider" do
    integration = create_connected_integration

    patch company_project_integration_path(@project, integration), params: {
      enabled_capabilities: [ "repositories.read" ]
    }

    assert_redirected_to company_project_integrations_path(@project)
    assert_equal [ "repositories.read" ], integration.reload.azure_enabled_capabilities
  end

  test "an Azure connection is not routed through the Coder settings path" do
    integration = create_connected_integration

    # Coder's own service refuses a non-Coder row; reaching it at all would mean
    # the Azure branch never ran.
    patch company_project_integration_path(@project, integration), params: {
      enabled_capabilities: [ "repositories.read" ]
    }

    assert_equal "Integration settings saved", flash[:notice]
    refute_match(/Only Coder integrations/, flash[:alert].to_s)
  end

  # Regression: `present?` meant unticking every box submitted an empty list that
  # was read as "said nothing", so the one edit a user makes to revoke everything
  # was the one that silently did not work.
  test "unticking every capability revokes them all" do
    integration = create_connected_integration

    patch company_project_integration_path(@project, integration), params: { enabled_capabilities: [] }

    assert_empty integration.reload.azure_enabled_capabilities
  end

  test "an unknown capability is not persisted on create" do
    stub_azure_token(tenant_id: @installation.tenant_id)
    stub_project_get

    post company_project_integrations_path(@project), params: {
      provider: "azure_devops", azure_devops_installation_id: @installation.id,
      azure_project_id: @azure_project_id,
      enabled_capabilities: [ "repositories.read", "project_collection_administer" ]
    }

    integration = Integration.where(provider: "azure_devops").last
    assert_equal %w[repositories.read], integration.azure_enabled_capabilities
  end

  # Regression: mark_error used save!, and the commonest way to reach it is a
  # connection whose Azure project has left the approved scope — which is exactly
  # what the model rejects, so recording the failure raised a 500 instead.
  test "a connection outside the approved scope reports the failure instead of raising" do
    integration = create_connected_integration
    @installation.update!(allowed_project_ids: [ SecureRandom.uuid ])

    post test_connection_company_project_integration_path(@project, integration)

    assert_response :redirect
    assert_match(/Connection failed/, flash[:alert])
    assert integration.reload.error?
    assert_equal "not_authorized", integration.settings["error"]
  end

  # `settings` reaches the browser whole, which IntegrationResource's own comment
  # states as an invariant: provider text does not belong in it, and a repaired
  # connection must not keep shipping the old failure.
  test "only the stable error code is stored, and a successful re-verify clears it" do
    integration = create_connected_integration
    stub_azure_token(tenant_id: @installation.tenant_id)
    stub_request(:get, %r{/_apis/projects/}).to_return(
      status: 403, headers: { "Content-Type" => "application/json" },
      body: { message: "TF400813: The user 'x' is not authorized to access this resource." }.to_json
    )
    post test_connection_company_project_integration_path(@project, integration)

    settings = integration.reload.settings
    assert_equal "permission_denied", settings["error"]
    refute settings.key?("error_message")
    refute_match(/TF400813/, settings.to_json)

    stub_project_get
    post test_connection_company_project_integration_path(@project, integration)

    assert integration.reload.active?
    refute integration.settings.key?("error")
  end

  test "test_connection re-verifies without mutating anything in Azure" do
    integration = create_connected_integration
    stub_azure_token(tenant_id: @installation.tenant_id)
    stub_project_get

    post test_connection_company_project_integration_path(@project, integration)

    assert_equal "Connection verified", flash[:notice]
    assert integration.reload.active?
  end

  test "a failed test marks the connection without destroying it or its repositories" do
    integration = create_connected_integration
    repository = create(:repository, :azure_devops, integration: integration, scope: @project)
    stub_azure_token(tenant_id: @installation.tenant_id)
    stub_request(:get, %r{/_apis/projects/}).to_return(status: 404, body: "")

    post test_connection_company_project_integration_path(@project, integration)

    assert_match(/Connection failed/, flash[:alert])
    assert integration.reload.error?
    assert Repository.exists?(repository.id)
  end

  private

  def create_connected_integration
    stub_azure_token(tenant_id: @installation.tenant_id)
    stub_project_get
    AzureDevops::IntegrationService.new(company: @company, connected_by: @user, project: @project)
                                   .create_with_installation(installation_id: @installation.id,
                                                             azure_project_id: @azure_project_id)
  end

  def stub_projects_list
    stub_request(:get, %r{/_apis/projects}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: {
        value: [
          { id: @azure_project_id, name: "Customer Platform", visibility: "private", state: "wellFormed" },
          { id: SecureRandom.uuid, name: "Unapproved", visibility: "private", state: "wellFormed" }
        ]
      }.to_json
    )
  end

  def stub_project_get
    stub_request(:get, %r{/_apis/projects/#{@azure_project_id}}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: @azure_project_id, name: "Customer Platform" }.to_json
    )
  end
end
