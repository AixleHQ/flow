# frozen_string_literal: true

require "test_helper"

# The Azure tool handlers, through their real services and a WebMock'd Azure.
# The point of these tests is the authorization chain and the retry contract —
# `requires_integration` only answers "is some Azure connection present in this
# project", and the MCP annotations are display hints the spec itself calls
# untrusted. Neither decides whether THIS call may touch THIS target.
class InternalTools::AzureDevopsToolsTest < ActiveSupport::TestCase
  setup do
    with_azure_devops_enabled
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @integration = create(:integration, :azure_devops, :active, company: @company, connected_by: @user)
    @project = @integration.project
    @repository = create(:repository, :azure_devops, integration: @integration, scope: @project,
                                      azure_repository_name: "api")
    @session = create(:terminal_session, :running, user: @user, project: @project)
    @session.repositories << @repository
    stub_azure_token(tenant_id: @integration.azure_devops_installation.tenant_id)
  end

  def run_tool(klass, params)
    klass.new(params: params, session: @session).execute
  end

  def organization = @integration.azure_organization_slug
  def azure_project = @integration.azure_project_id

  # == target resolution ==

  test "a repository tool refuses a repository that is not attached to this session" do
    other = create(:repository, :azure_devops, integration: @integration, scope: @project)

    result = run_tool(InternalTools::AzureDevopsListPullRequests, { repository_id: other.id })

    assert_equal 1, result[:exit_code]
    assert_match(/not_authorized/, result[:stderr])
  end

  test "a repository tool refuses a repository owned by another project" do
    foreign = create(:integration, :azure_devops, :active)
    foreign_repository = create(:repository, :azure_devops, integration: foreign, scope: foreign.project)
    @session.repositories << foreign_repository

    result = run_tool(InternalTools::AzureDevopsListPullRequests, { repository_id: foreign_repository.id })

    assert_equal 1, result[:exit_code]
    assert_match(/another project/, result[:stderr])
  end

  test "a work item tool requires an explicit connection rather than picking one" do
    result = run_tool(InternalTools::AzureDevopsGetWorkItem, { work_item_id: 5 })

    assert_equal 1, result[:exit_code]
    assert_match(/integration_id is required/, result[:stderr])
  end

  test "a work item tool refuses a connection from another project" do
    foreign = create(:integration, :azure_devops, :active)

    result = run_tool(InternalTools::AzureDevopsGetWorkItem, { integration_id: foreign.id, work_item_id: 5 })

    assert_equal 1, result[:exit_code]
    assert_match(/another project/, result[:stderr])
  end

  test "a disabled capability is refused before any Azure request" do
    @integration.settings = @integration.settings.merge("enabled_capabilities" => [ "repositories.read" ])
    @integration.save!

    result = run_tool(InternalTools::AzureDevopsAddWorkItemComment,
                      { integration_id: @integration.id, work_item_id: 5, text: "hi", operation_key: "k1" })

    assert_equal 1, result[:exit_code]
    assert_match(/work_items.write/, result[:stderr])
  end

  # == list_connections ==

  test "list_connections reports the profile and never a credential" do
    result = run_tool(InternalTools::AzureDevopsListConnections, {})

    assert_equal 0, result[:exit_code]
    body = JSON.parse(result[:stdout])
    connection = body["connections"].first
    assert_equal @integration.id, connection["integration_id"]
    assert_equal "service_principal", connection["auth_mode"]
    assert_includes connection["capabilities"], "pull_requests.write"
    refute_match(/token|secret|password/i, result[:stdout])
    assert_equal @repository.id, body["repositories"].first["repository_id"]
  end

  # == pull requests ==

  test "creating a pull request qualifies the refs and defaults to draft" do
    create_url = "#{AZURE_API_HOST}/#{organization}/#{azure_project}/_apis/git/repositories/" \
                 "#{@repository.external_id}/pullrequests"
    stub_request(:post, create_url)
      .with(query: { "api-version" => "7.1" })
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: pr_payload.to_json)

    result = run_tool(InternalTools::AzureDevopsCreatePullRequest, {
      repository_id: @repository.id, source_branch: "feature/1", target_branch: "main",
      title: "Fix", description: "body", operation_key: "pr-1"
    })

    assert_equal 0, result[:exit_code]
    assert_requested(:post, create_url, query: { "api-version" => "7.1" }) do |req|
      body = JSON.parse(req.body)
      body["sourceRefName"] == "refs/heads/feature/1" &&
        body["targetRefName"] == "refs/heads/main" &&
        body["isDraft"] == true
    end
  end

  test "replaying an operation key returns the first result instead of opening a second pull request" do
    stub = stub_request(:post, %r{/pullrequests})
           .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: pr_payload.to_json)

    params = {
      repository_id: @repository.id, source_branch: "feature/1", target_branch: "main",
      title: "Fix", description: "body", operation_key: "pr-replay"
    }
    run_tool(InternalTools::AzureDevopsCreatePullRequest, params)
    second = run_tool(InternalTools::AzureDevopsCreatePullRequest, params)

    assert_equal 0, second[:exit_code]
    assert JSON.parse(second[:stdout])["replayed"]
    assert_requested stub, times: 1
  end

  test "the same operation key with a different request is a conflict" do
    stub_request(:post, %r{/pullrequests})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: pr_payload.to_json)

    base = {
      repository_id: @repository.id, source_branch: "feature/1", target_branch: "main",
      title: "Fix", operation_key: "pr-conflict"
    }
    run_tool(InternalTools::AzureDevopsCreatePullRequest, base)
    second = run_tool(InternalTools::AzureDevopsCreatePullRequest, base.merge(title: "Different"))

    assert_equal 1, second[:exit_code]
    assert_match(/conflict/, second[:stderr])
  end

  test "a dispatched write whose answer never arrives is unknown, and is not retried automatically" do
    stub = stub_request(:post, %r{/pullrequests}).to_timeout

    result = run_tool(InternalTools::AzureDevopsCreatePullRequest, {
      repository_id: @repository.id, source_branch: "feature/1", target_branch: "main",
      title: "Fix", operation_key: "pr-unknown"
    })

    assert_equal 1, result[:exit_code]
    assert_match(/outcome_unknown/, result[:stderr])
    assert_match(/duplicate/, result[:stderr])
    assert_requested stub, times: 1

    # The recorded outcome survives, so a replay reports "unknown" rather than
    # quietly issuing the write a second time.
    replay = run_tool(InternalTools::AzureDevopsCreatePullRequest, {
      repository_id: @repository.id, source_branch: "feature/1", target_branch: "main",
      title: "Fix", operation_key: "pr-unknown"
    })
    assert_match(/outcome_unknown/, replay[:stderr])
    assert_requested stub, times: 1
  end

  test "changed files are reported as metadata, not as a diff" do
    stub_request(:get, %r{/pullrequests/7/iterations\?})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { value: [ { id: 1 }, { id: 2 } ] }.to_json)
    stub_request(:get, %r{/iterations/2/changes})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { changeEntries: [ { item: { path: "/app/x.rb" }, changeType: "edit" } ] }.to_json)

    result = run_tool(InternalTools::AzureDevopsGetPullRequestChanges,
                      { repository_id: @repository.id, pull_request_id: 7 })

    body = JSON.parse(result[:stdout])
    assert_equal 2, body["iteration"]
    assert_equal false, body["diff_available"] # rubocop:disable Minitest/RefuteFalse
    assert_match(/does not return a textual patch/, body["note"])
  end

  test "a pull request from another repository is refused rather than returned" do
    stub_request(:get, %r{/pullrequests/7})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: pr_payload(repository_id: SecureRandom.uuid).to_json)

    result = run_tool(InternalTools::AzureDevopsGetPullRequest,
                      { repository_id: @repository.id, pull_request_id: 7 })

    assert_equal 1, result[:exit_code]
    assert_match(/not in this repository/, result[:stderr])
  end

  # == work items ==

  test "a work item query pins the selected project and escapes its values" do
    wiql_url = "#{AZURE_API_HOST}/#{organization}/#{azure_project}/_apis/wit/wiql"
    stub_request(:post, wiql_url)
      .with(query: { "api-version" => "7.1", "$top" => "1000" })
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { workItems: [] }.to_json)

    run_tool(InternalTools::AzureDevopsQueryWorkItems,
             { integration_id: @integration.id, title_contains: "it's broken" })

    assert_requested(:post, wiql_url, query: { "api-version" => "7.1", "$top" => "1000" }) do |req|
      query = JSON.parse(req.body)["query"]
      query.include?("[System.TeamProject] = @project") &&
        query.include?("'it''s broken'") &&
        query.include?("ORDER BY [System.Id] DESC")
    end
  end

  test "a work item update guards the revision with a JSON Patch test" do
    stub_request(:patch, %r{/_apis/wit/workitems/11})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id: 11, rev: 4, fields: { "System.Title" => "t" } }.to_json)

    run_tool(InternalTools::AzureDevopsUpdateWorkItem,
             { integration_id: @integration.id, work_item_id: 11, expected_revision: 3, state: "Active" })

    assert_requested(:patch, %r{/_apis/wit/workitems/11}) do |req|
      patch = JSON.parse(req.body)
      patch.first == { "op" => "test", "path" => "/rev", "value" => 3 } &&
        patch.any? { |op| op["path"] == "/fields/System.State" } &&
        req.headers["Content-Type"].include?("application/json-patch+json")
    end
  end

  test "a work item update rejects a field the tool does not expose" do
    result = InternalTools::AzureDevopsUpdateWorkItem.new(
      params: { integration_id: @integration.id, work_item_id: 11 }, session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_match(/No fields to update/, result[:stderr])
  end

  test "linking a pull request never transitions the work item" do
    stub_request(:get, %r{/pullrequests/7})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: pr_payload.to_json)
    stub_request(:patch, %r{/_apis/wit/workitems/11})
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id: 11, rev: 5, fields: {} }.to_json)

    run_tool(InternalTools::AzureDevopsLinkWorkItem,
             { repository_id: @repository.id, pull_request_id: 7, work_item_id: 11 })

    assert_requested(:patch, %r{/_apis/wit/workitems/11}) do |req|
      patch = JSON.parse(req.body)
      patch.any? { |op| op.dig("value", "rel") == "ArtifactLink" } &&
        patch.none? { |op| op["path"].to_s.include?("System.State") }
    end
  end

  private

  def pr_payload(repository_id: nil)
    {
      pullRequestId: 7,
      title: "Fix",
      description: "body",
      status: "active",
      isDraft: true,
      sourceRefName: "refs/heads/feature/1",
      targetRefName: "refs/heads/main",
      createdBy: { displayName: "Aixle" },
      repository: {
        id: repository_id || @repository.external_id,
        project: { id: @integration.azure_project_id }
      }
    }
  end
end
