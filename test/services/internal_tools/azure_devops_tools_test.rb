# frozen_string_literal: true

require "test_helper"

# The Azure tool handlers over the canonical adapter fakes (R3), not over
# WebMock: `stub_request` belongs in the adapter contract tests in
# test/services/azure_devops/, which are what keep these fakes honest (R4).
#
# CredentialProvider and Client stay real, because the authorization chain is
# what these tests are about — `requires_integration` only answers "is some
# Azure connection present in this project", and the MCP annotations are display
# hints the spec itself calls untrusted. Neither decides whether THIS call may
# touch THIS target.
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
    @fakes = stub_azure_devops!(integration: @integration)
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
    result = run_tool(InternalTools::AzureDevopsCreatePullRequest, {
      repository_id: @repository.id, source_branch: "feature/1", target_branch: "main",
      title: "Fix", description: "body", operation_key: "pr-1"
    })

    assert_equal 0, result[:exit_code]
    call = @fakes.pull_requests.last_call
    assert_equal :create, call[:method]
    assert_equal "feature/1", call[:source_branch]
    assert_equal "main", call[:target_branch]
    # Draft unless explicitly asked otherwise; the ref qualification itself is
    # pinned by the adapter's own contract test.
    assert_equal true, call[:draft] # rubocop:disable Minitest/AssertTruthy
  end

  test "replaying an operation key returns the first result instead of opening a second pull request" do
    params = {
      repository_id: @repository.id, source_branch: "feature/1", target_branch: "main",
      title: "Fix", description: "body", operation_key: "pr-replay"
    }
    run_tool(InternalTools::AzureDevopsCreatePullRequest, params)
    second = run_tool(InternalTools::AzureDevopsCreatePullRequest, params)

    assert_equal 0, second[:exit_code]
    assert JSON.parse(second[:stdout])["replayed"]
    assert_equal 1, @fakes.pull_requests.calls_to(:create).size
  end

  test "the same operation key with a different request is a conflict" do
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
    # OutcomeUnknown is what the adapter raises for a write it cannot confirm;
    # the contract test pins which transport failures produce it.
    @fakes.pull_requests.instance_variable_set(:@error, AzureDevops::OutcomeUnknown.new("no answer"))

    result = run_tool(InternalTools::AzureDevopsCreatePullRequest, {
      repository_id: @repository.id, source_branch: "feature/1", target_branch: "main",
      title: "Fix", operation_key: "pr-unknown"
    })

    assert_equal 1, result[:exit_code]
    assert_match(/outcome_unknown/, result[:stderr])
    assert_match(/duplicate/, result[:stderr])
    assert_equal 1, @fakes.pull_requests.calls_to(:create).size

    # The recorded outcome survives, so a replay reports "unknown" rather than
    # quietly issuing the write a second time.
    replay = run_tool(InternalTools::AzureDevopsCreatePullRequest, {
      repository_id: @repository.id, source_branch: "feature/1", target_branch: "main",
      title: "Fix", operation_key: "pr-unknown"
    })
    assert_match(/outcome_unknown/, replay[:stderr])
    assert_equal 1, @fakes.pull_requests.calls_to(:create).size
  end

  test "changed files are reported as metadata, not as a diff" do
    result = run_tool(InternalTools::AzureDevopsGetPullRequestChanges,
                      { repository_id: @repository.id, pull_request_id: 7 })

    body = JSON.parse(result[:stdout])
    assert_equal false, body["diff_available"] # rubocop:disable Minitest/RefuteFalse
    assert_match(/does not return a textual patch/, body["note"])
  end

  # Cross-repository scope is enforced inside the adapter (and pinned by its own
  # contract test); here it is the tool's error translation that is asserted.
  test "a pull request the adapter refuses as out of scope surfaces as not_authorized" do
    @fakes.pull_requests.instance_variable_set(
      :@error, AzureDevops::NotAuthorized.new("That pull request is not in this repository")
    )

    result = run_tool(InternalTools::AzureDevopsGetPullRequest,
                      { repository_id: @repository.id, pull_request_id: 7 })

    assert_equal 1, result[:exit_code]
    assert_match(/not_authorized/, result[:stderr])
    assert_match(/not in this repository/, result[:stderr])
  end

  # == work items ==

  # The WIQL text itself — the pinned project predicate, the quote escaping, the
  # deterministic order — is asserted in the adapter's own unit test. Here the
  # tool's job is to pass the caller's structured filters through untouched.
  test "a work item query passes structured filters to the adapter" do
    run_tool(InternalTools::AzureDevopsQueryWorkItems,
             { integration_id: @integration.id, title_contains: "it's broken", open_only: true })

    call = @fakes.work_items.last_call
    assert_equal :query, call[:method]
    assert_equal "it's broken", call[:filters][:title_contains]
    assert call[:filters][:open_only]
  end

  # The JSON Patch shape (the `test` on /rev, the json-patch content type) is
  # pinned by the adapter's contract test; the tool's job is to forward the
  # expected revision rather than dropping it.
  test "a work item update forwards the expected revision" do
    run_tool(InternalTools::AzureDevopsUpdateWorkItem,
             { integration_id: @integration.id, work_item_id: 11, expected_revision: 3, state: "Active" })

    call = @fakes.work_items.last_call
    assert_equal :update, call[:method]
    assert_equal 3, call[:expected_revision]
    assert_equal "Active", call[:fields][:state]
  end

  test "a work item update rejects a field the tool does not expose" do
    result = InternalTools::AzureDevopsUpdateWorkItem.new(
      params: { integration_id: @integration.id, work_item_id: 11 }, session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_match(/No fields to update/, result[:stderr])
  end

  test "linking a pull request reads the pull request first and never sends a state change" do
    run_tool(InternalTools::AzureDevopsLinkWorkItem,
             { repository_id: @repository.id, pull_request_id: 7, work_item_id: 11 })

    # Both ends are re-checked against this connection before the link is made.
    assert @fakes.pull_requests.called?(:get)

    call = @fakes.work_items.last_call
    assert_equal :link_pull_request, call[:method]
    assert_match(%r{vstfs:///Git/PullRequestId/}, call[:artifact_id])
    # Linking is separate from transitioning: no field write accompanies it.
    assert_empty @fakes.work_items.calls_to(:update)
  end
end
