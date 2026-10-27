# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # Connecting an organization through the customer's own Entra app. There is no
  # administrator credential here, so the interesting questions are what the token
  # exchange proves, what is left behind when it or a later check fails, and that
  # one company's connection never speaks for another's.
  #
  # Azure surfaces are pinned with WebMock using the shapes in Microsoft's
  # documentation; nothing here has run against a live tenant.
  class FederatedOnboardingTest < ActiveSupport::TestCase
    setup do
      with_azure_devops_federation_only
      @company = create(:company)
      @actor = create(:user, :admin, company: @company)
      @tenant = "79e1cf7c-9e26-468d-81f6-ce6f3b9783dd"
      @client_id = SecureRandom.uuid
      @oid = "9550df62-80e0-4551-821e-ba38e4a7e876"
      @project_id = SecureRandom.uuid
      @second_project_id = SecureRandom.uuid
      @sent_assertions = []
      @onboarding = FederatedOnboarding.new(company: @company, actor: @actor)

      stub_tenant
      stub_exchange
      stub_projects([ { id: @project_id, name: "Customer Platform" }, { id: @second_project_id, name: "Payments" } ])
      stub_permission_surfaces
    end

    def stub_tenant(organization: "contoso")
      stub_request(:get, %r{#{AZURE_API_HOST}/#{organization}/_apis/git/repositories})
        .to_return(status: 302, headers: { "WWW-Authenticate" => "Bearer authorization_uri=#{AZURE_TOKEN_HOST}/#{@tenant}" })
    end

    # The app token carries the service principal's object id as `oid`.
    def app_token(oid = @oid)
      "h.#{Base64.urlsafe_encode64({ oid: oid }.to_json, padding: false)}.s"
    end

    def stub_exchange(status: 200, body: nil)
      stub_request(:post, "#{AZURE_TOKEN_HOST}/#{@tenant}/oauth2/v2.0/token").to_return do |request|
        @sent_assertions << JWT.decode(Rack::Utils.parse_query(request.body)["client_assertion"], nil, false).first
        { status: status, headers: { "Content-Type" => "application/json" },
          body: (body || { access_token: app_token, token_type: "Bearer", expires_in: 3600 }).to_json }
      end
    end

    def stub_projects(projects)
      stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/projects\?.*\$top})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { value: projects }.to_json)
    end

    # Every namespace defines every action and Azure allows everything, until a
    # test narrows it down.
    def stub_permission_surfaces(granted: true)
      actions = %w[GenericRead GenericContribute CreateBranch PullRequestContribute WORK_ITEM_READ WORK_ITEM_WRITE
                   ViewBuilds ViewSubscriptions EditSubscriptions].each_with_index.map { |name, i| { name: name, bit: 2**i } }
      json = { "Content-Type" => "application/json" }
      stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/securitynamespaces/.+})
        .to_return(status: 200, headers: json, body: { count: 1, value: [ { actions: actions } ] }.to_json)
      stub_request(:get, %r{#{AZURE_API_HOST}/contoso/[^/]+/_apis/wit/classificationnodes/areas})
        .to_return(status: 200, headers: json, body: { identifier: SecureRandom.uuid }.to_json)
      stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/permissions/})
        .to_return(status: 200, headers: json, body: { count: 1, value: [ granted ] }.to_json)
    end

    def complete(**overrides)
      @onboarding.complete!(organization: "contoso", client_id: @client_id, project_ids: [ @project_id ], **overrides)
    end

    # == inspect ==

    test "inspect lists what the app can see and writes nothing" do
      result = @onboarding.inspect!(organization: "contoso", client_id: @client_id)

      assert_equal "contoso", result.organization
      assert_equal @tenant, result.tenant_id
      assert_equal [ "Customer Platform", "Payments" ], result.projects.pluck(:name)
      assert_nil result.permissions
      assert_not result.already_bound
      assert_equal 0, AzureDevopsInstallation.count
    end

    test "inspect reports the app's permissions in the projects it is asked about" do
      stub_permission_surfaces(granted: false)

      result = @onboarding.inspect!(organization: "contoso", client_id: @client_id, project_ids: [ @project_id ])

      assert_not result.permissions.ok?
      assert_equal [ @project_id ], result.permissions.projects.map(&:project_id)
    end

    test "the assertion names this company and the deployment's issuer" do
      @onboarding.inspect!(organization: "contoso", client_id: @client_id)

      assert_equal "aixle:company:#{@company.public_id}", @sent_assertions.last["sub"]
      assert_equal AzureDevopsTestHelper::FEDERATION_ISSUER, @sent_assertions.last["iss"]
    end

    test "inspect says so when the customer's credential does not match" do
      stub_exchange(status: 401, body: { error: "invalid_client",
                                         error_description: "AADSTS700213: No matching federated identity record." })

      error = assert_raises(FederationRejected) { @onboarding.inspect!(organization: "contoso", client_id: @client_id) }

      assert_match(/subject/, error.message)
      assert_equal 0, AzureDevopsInstallation.count
    end

    test "is not available on a deployment that cannot act as an issuer" do
      with_azure_devops_enabled

      assert_raises(IntegrationUnavailable) { @onboarding.inspect!(organization: "contoso", client_id: @client_id) }
    end

    # == complete ==

    test "records a federated binding that needs no operator app and no administrator" do
      installation = complete

      assert_predicate installation, :active?
      assert_predicate installation, :federated?
      assert_nil installation.app_config_key
      assert_equal @client_id, installation.client_id
      assert_equal @tenant, installation.tenant_id
      assert_equal @oid, installation.service_principal_object_id
      assert_equal [ @project_id ], installation.allowed_project_ids
      assert_equal @actor, installation.approved_by
      assert_not_nil installation.last_verified_at
    end

    test "the installation can then serve tokens like any other" do
      installation = complete

      assert_equal app_token, AppTokenService.new(installation).access_token.value
    end

    test "reconnecting widens the approved projects" do
      complete
      installation = complete(project_ids: [ @second_project_id ])

      assert_equal [ @project_id, @second_project_id ].sort, installation.allowed_project_ids.sort
      assert_equal 1, AzureDevopsInstallation.count
    end

    test "a project the app cannot see is refused and nothing is left behind" do
      error = assert_raises(Error) { complete(project_ids: [ SecureRandom.uuid ]) }

      assert_equal "project_not_granted", error.code
      assert_equal 0, AzureDevopsInstallation.count
    end

    test "missing required permissions refuse the connection and name them" do
      stub_permission_surfaces(granted: false)

      error = assert_raises(Error) { complete }

      assert_equal "permissions_missing", error.code
      assert_match(/Customer Platform: Repos/, error.message)
      assert_equal 0, AzureDevopsInstallation.count
    end

    test "permissions that could not be checked do not stop a connection" do
      stub_request(:get, %r{#{AZURE_API_HOST}/contoso/_apis/securitynamespaces/.+}).to_return(status: 404)

      assert_predicate complete, :active?
    end

    test "a failed exchange leaves nothing behind" do
      stub_exchange(status: 401, body: { error: "invalid_client", error_description: "AADSTS700213: no match" })

      assert_raises(FederationRejected) { complete }
      assert_equal 0, AzureDevopsInstallation.count
    end

    test "at least one project must be chosen" do
      assert_raises(ValidationFailed) { complete(project_ids: []) }
    end

    test "an organization connected through Aixle's Microsoft app is not silently switched" do
      shared = create(:azure_devops_installation, :active, :approved, company: @company, tenant_id: @tenant,
                                                                      organization_slug: "contoso")

      error = assert_raises(ValidationFailed) { complete }

      assert_match(/already connected through Aixle/, error.message)
      assert_equal "shared_app", shared.reload.credential_kind
    end

    test "connecting with a recreated app moves the binding and keeps only what the new app can reach" do
      old_client = SecureRandom.uuid
      old = create(:azure_devops_installation, :federated, :active, :approved, company: @company, tenant_id: @tenant,
                                                                               organization_slug: "contoso", client_id: old_client,
                                                                               service_principal_object_id: SecureRandom.uuid,
                                                                               allowed_project_ids: [ @project_id, SecureRandom.uuid ])
      new_oid = SecureRandom.uuid
      stub_exchange(body: { access_token: app_token(new_oid), expires_in: 3600 })

      installation = complete(project_ids: [ @second_project_id ])

      assert_equal old.id, installation.id
      assert_equal @client_id, installation.client_id
      assert_equal new_oid, installation.service_principal_object_id
      assert_equal [ @project_id, @second_project_id ].sort, installation.allowed_project_ids.sort
    end

    test "a failed move to a new app leaves the existing binding as it was" do
      old_client = SecureRandom.uuid
      old = create(:azure_devops_installation, :federated, :active, :approved, company: @company, tenant_id: @tenant,
                                                                               organization_slug: "contoso", client_id: old_client,
                                                                               service_principal_object_id: @oid,
                                                                               allowed_project_ids: [ @project_id ])
      stub_exchange(status: 401, body: { error: "invalid_client", error_description: "AADSTS700213: no match" })

      assert_raises(FederationRejected) { complete }

      old.reload
      assert_equal old_client, old.client_id
      assert_predicate old, :active?
    end

    test "another company gets its own binding, signed with its own subject" do
      complete
      other = create(:company)
      FederatedOnboarding.new(company: other, actor: create(:user, :admin, company: other))
                         .complete!(organization: "contoso", client_id: @client_id, project_ids: [ @project_id ])

      assert_equal 2, AzureDevopsInstallation.count
      assert_equal [ "aixle:company:#{@company.public_id}", "aixle:company:#{other.public_id}" ].sort,
                   @sent_assertions.pluck("sub").uniq.sort
    end
  end
end
