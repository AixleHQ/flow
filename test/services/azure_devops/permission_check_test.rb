# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # Contract test (R4) for the permission evaluation. The Azure DevOps surface is
  # pinned with WebMock; payload shapes follow Microsoft's documentation for
  # `securitynamespaces` and `permissions`, and have not been run against a live
  # organization.
  class PermissionCheckTest < ActiveSupport::TestCase
    ORG = "contoso"
    AREA_ROOT = "9c2f0c41-6a7a-4a5e-a1de-0f5a0f6a0a11"

    ACTIONS = {
      PermissionCheck::GIT_NAMESPACE => { "GenericRead" => 2, "GenericContribute" => 4, "CreateBranch" => 16,
                                          "PullRequestContribute" => 16_384 },
      PermissionCheck::CLASSIFICATION_NAMESPACE => { "WORK_ITEM_READ" => 16, "WORK_ITEM_WRITE" => 32 },
      PermissionCheck::BUILD_NAMESPACE => { "ViewBuilds" => 1 },
      PermissionCheck::SERVICE_HOOKS_NAMESPACE => { "ViewSubscriptions" => 1, "EditSubscriptions" => 2 }
    }.freeze

    setup do
      with_azure_devops_federation_only
      @project_id = SecureRandom.uuid
      @projects = [ { id: @project_id, name: "Customer Platform" } ]
      token = AppTokenService::Token.new(value: "app-token", expires_at: 1.hour.from_now)
      credential = CredentialProvider::Resolved.new(
        integration: nil, installation: nil, mode: :service_principal, organization: ORG, project_id: nil,
        token_service: FederatedOnboarding::FixedToken.new(token)
      )
      @client = Client.new(credential: credential, organization: ORG)

      ACTIONS.each_key { |namespace| stub_namespace(namespace) }
      stub_area_root
      ACTIONS.each_key { |namespace| stub_all_permissions(namespace, true) }
    end

    def check
      PermissionCheck.new(client: @client).call(@projects)
    end

    def stub_namespace(namespace, status: 200)
      actions = ACTIONS.fetch(namespace).map { |name, bit| { name: name, displayName: name, bit: bit } }
      stub_request(:get, "#{AZURE_API_HOST}/#{ORG}/_apis/securitynamespaces/#{namespace}")
        .with(query: { "api-version" => "7.1" })
        .to_return(status: status, headers: { "Content-Type" => "application/json" },
                   body: { count: 1, value: [ { namespaceId: namespace, actions: actions } ] }.to_json)
    end

    def stub_area_root
      stub_request(:get, "#{AZURE_API_HOST}/#{ORG}/#{@project_id}/_apis/wit/classificationnodes/areas")
        .with(query: { "$depth" => "0", "api-version" => "7.1" })
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { identifier: AREA_ROOT, name: "Customer Platform", structureType: "area" }.to_json)
    end

    def token_for(check)
      { repository: "repoV2/#{@project_id}", project: @project_id,
        service_hooks: "PublisherSecurity/#{@project_id}",
        area_path: "vstfs:///Classification/Node/#{AREA_ROOT}" }.fetch(check.token)
    end

    def stub_permission(check, granted, body: nil)
      bit = ACTIONS.fetch(check.namespace).fetch(check.action)
      stub_request(:get, "#{AZURE_API_HOST}/#{ORG}/_apis/permissions/#{check.namespace}/#{bit}")
        .with(query: { "tokens" => token_for(check), "api-version" => "7.1" })
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: (body || { count: 1, value: [ granted ] }).to_json)
    end

    def stub_all_permissions(namespace, granted)
      PermissionCheck::CHECKS.select { |c| c.namespace == namespace }.each { |c| stub_permission(c, granted) }
    end

    def check_named(key) = PermissionCheck::CHECKS.find { |c| c.key == key }

    def status_of(report, key) = report.projects.first.items.find { |i| i.key == key }.status

    test "reports every permission as granted when Azure allows them all" do
      report = check

      assert_predicate report, :ok?
      assert report.projects.first.items.all? { |item| item.status == :granted }
      assert_nil report.summary
    end

    test "a missing required permission blocks and is named by project and group" do
      stub_permission(check_named("repos_create_branch"), false)

      report = check

      assert_not report.ok?
      assert_equal :missing, status_of(report, "repos_create_branch")
      assert_equal "Customer Platform: Repos → Create branch", report.summary
    end

    test "a missing optional permission is reported but does not block" do
      stub_permission(check_named("builds_view"), false)
      stub_permission(check_named("hooks_edit"), false)

      report = check

      assert_predicate report, :ok?
      assert_equal :missing, status_of(report, "builds_view")
      assert_equal :missing, status_of(report, "hooks_edit")
    end

    test "asks for permissions by the bit the namespace itself names" do
      check

      assert_requested :get, "#{AZURE_API_HOST}/#{ORG}/_apis/permissions/#{PermissionCheck::GIT_NAMESPACE}/16384",
                       query: { "tokens" => "repoV2/#{@project_id}", "api-version" => "7.1" }
    end

    test "an unavailable namespace leaves its permissions unknown, never missing" do
      stub_request(:get, "#{AZURE_API_HOST}/#{ORG}/_apis/securitynamespaces/#{PermissionCheck::GIT_NAMESPACE}")
        .with(query: { "api-version" => "7.1" }).to_return(status: 404)

      report = check

      assert_equal :unknown, status_of(report, "repos_contribute")
      assert_predicate report, :ok?
    end

    test "an action the namespace does not define is unknown" do
      stub_request(:get, "#{AZURE_API_HOST}/#{ORG}/_apis/securitynamespaces/#{PermissionCheck::BUILD_NAMESPACE}")
        .with(query: { "api-version" => "7.1" })
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { count: 1, value: [ { actions: [ { name: "Other", bit: 8 } ] } ] }.to_json)

      assert_equal :unknown, status_of(check, "builds_view")
    end

    test "an answer of the wrong shape is unknown" do
      stub_permission(check_named("repos_read"), true, body: { count: 2, value: [ true, true ] })

      assert_equal :unknown, status_of(check, "repos_read")
    end

    test "without an area path root the Boards permissions are unknown" do
      stub_request(:get, "#{AZURE_API_HOST}/#{ORG}/#{@project_id}/_apis/wit/classificationnodes/areas")
        .with(query: { "$depth" => "0", "api-version" => "7.1" }).to_return(status: 404)

      report = check

      assert_equal :unknown, status_of(report, "boards_edit")
      assert_equal :granted, status_of(report, "repos_read")
    end

    test "serialises for the browser without anything but the facts" do
      stub_permission(check_named("repos_read"), false)

      payload = check.to_h
      item = payload[:projects].first[:items].find { |i| i[:key] == "repos_read" }

      refute payload[:ok]
      assert_equal({ key: "repos_read", group: "Repos", label: "Read", required: true, status: :missing }, item)
    end
  end
end
